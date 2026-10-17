import Foundation
import os

extension ModelTextInvocation {
    static func fallback(primary: Self, fallback: Self?, capability: ModelConfiguration.Capability,
                         version: String, fallbackUnavailable: Bool = false, validate: @escaping @Sendable () async throws -> Void) -> Self {
        let flow = ModelFallback(primary: primary, fallback: fallback, capability: capability, validate: validate)
        let observed = OSAllocatedUnfairLock<String?>(initialState: nil)
        var invocation = Self(version: version, modelID: { observed.withLock { $0 } }, generateWithEvents: { request, partial, onEvent in
            let budget = min(request.timeout, capability == .fast ? 120 : 300)
            guard budget > 0 else { throw ModelDeadline.expired }
            let deadline = ContinuousClock.now.advanced(by: .seconds(budget))
            let validity = ModelStreamValidity(deadline: deadline)
            let invocationID = UUID()
            defer { validity.invalidate() }
            let started = RuntimeLog.ticks()
            let readiness: RuntimeLog.FallbackState = fallback != nil ? .ready : fallbackUnavailable ? .unavailable : .none
            let log = RuntimeLog.current ?? RuntimeLog.Context()
            log.emit(.stageStarted, .init(stage: .modelChain, fallbackState: readiness))
            do {
                let output = try await withTaskCancellationHandler {
                    try await ModelDeadline.run(until: deadline) {
                        let output = try await flow.call(request, deadline: deadline, invocationID: invocationID,
                                                         validity: validity, onEvent: onEvent)
                        try await validate()
                        try await ModelValidation.current?()
                        return output
                    }
                } onCancel: { validity.invalidate() }
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else { throw ModelDeadline.expired }
                observed.withLock { $0 = output.model }
                // The legacy observer adopts only the completed, successful attempt.
                try await partial?(output.text)
                log.emit(.stageFinished, .init(stage: .modelChain, outcome: .success, actualModel: output.model,
                    durationMs: RuntimeLog.milliseconds(since: started), fallbackState: readiness))
                return output.text
            } catch {
                let code = RuntimeLog.code(error)
                log.emit(.stageFinished, .init(stage: .modelChain,
                    outcome: code == .cancelled ? .cancelled : code == .stale ? .discarded : code == .timeout ? .timeout : .failed,
                    errorCode: code, durationMs: RuntimeLog.milliseconds(since: started), fallbackState: readiness))
                throw error
            }
        })
        invocation.capability = capability
        invocation.requestTimeout = capability == .fast ? 120 : 300
        return invocation
    }
}

/// One queue per frozen flow. Queueing and both attempts consume the original monotonic deadline.
private actor ModelFallback {
    struct Output: Sendable { let text: String; let model: String? }
    let primary: ModelTextInvocation
    let fallback: ModelTextInvocation?
    let capability: ModelConfiguration.Capability
    let validate: @Sendable () async throws -> Void
    private var busy = false
    private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []

    init(primary: ModelTextInvocation, fallback: ModelTextInvocation?, capability: ModelConfiguration.Capability,
         validate: @escaping @Sendable () async throws -> Void) {
        self.primary = primary; self.fallback = fallback; self.capability = capability; self.validate = validate
    }
    func call(_ request: ModelTextRequest, deadline: ContinuousClock.Instant, invocationID: UUID,
              validity: ModelStreamValidity, onEvent: ModelTextInvocation.EventHandler?) async throws -> Output {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        try await validate()
        try await ModelValidation.current?()
        guard validity.isValid else { throw ModelDeadline.expired }
        let remaining = ModelDeadline.seconds(until: deadline)
        guard remaining > 0 else { throw ModelDeadline.expired }
        let primaryBudget = fallback == nil ? remaining : min(capability == .fast ? 30 : 120, remaining / 2)
        do {
            return try await attempt(primary, request: request,
                deadline: min(deadline, .now.advanced(by: .seconds(primaryBudget))), role: .primary,
                invocationID: invocationID, validity: validity, onEvent: onEvent)
        } catch {
            try Task.checkCancellation()
            try await validate()
            try await ModelValidation.current?()
            guard Self.canFallback(error), let fallback else { throw error }
            guard validity.isValid, ContinuousClock.now < deadline else { throw ModelDeadline.expired }
            RuntimeLog.current?.emit(.stageFinished, .init(stage: .service, outcome: .failed,
                errorCode: RuntimeLog.code(error), modelRole: .primary, fallbackReason: RuntimeLog.code(error)))
            return try await attempt(fallback, request: request, deadline: deadline, role: .fallback,
                                     invocationID: invocationID, validity: validity, onEvent: onEvent)
        }
    }
    private func attempt(_ invocation: ModelTextInvocation, request: ModelTextRequest,
                         deadline: ContinuousClock.Instant, role: RuntimeLog.ModelRole, invocationID: UUID,
                         validity: ModelStreamValidity, onEvent: ModelTextInvocation.EventHandler?) async throws -> Output {
        try Task.checkCancellation()
        try await validate()
        try await ModelValidation.current?()
        guard validity.isValid, ContinuousClock.now < deadline else { throw ModelDeadline.expired }
        var input = request; input.timeout = ModelDeadline.seconds(until: deadline)
        if capability == .deep { input.streaming = true }
        let frozen = input
        let attemptValidity = ModelStreamValidity(deadline: deadline, parent: validity)
        defer { attemptValidity.invalidate() }
        let started = RuntimeLog.ticks()
        var log = RuntimeLog.current ?? RuntimeLog.Context()
        log.provider = invocation.providerID
        let attemptID = UUID()
        let validate = self.validate
        let businessValidation = ModelValidation.current
        let publish: @Sendable (ModelStreamEvent.Kind) async throws -> Void = { kind in
            guard attemptValidity.isValid else { return }
            do {
                try Task.checkCancellation()
                try await validate()
                try await businessValidation?()
                guard attemptValidity.isValid else { return }
                try await onEvent?(.init(kind: kind, invocationID: invocationID, attemptID: attemptID,
                                         role: role, validity: attemptValidity))
            } catch { attemptValidity.invalidate(); throw error }
        }
        let partial: ModelTextInvocation.PartialHandler?
        if onEvent == nil { partial = nil }
        else { partial = { text in try await publish(.content(text)) } }
        log.emit(.callStarted, .init(stage: .service, requestedModel: invocation.expectedModelID, modelRole: role, attemptID: attemptID.uuidString))
        do {
            let text = try await withTaskCancellationHandler {
                try await RuntimeLog.$current.withValue(log) {
                    try await ModelDeadline.run(until: deadline) {
                        try await publish(.attemptStarted)
                        try Task.checkCancellation()
                        guard attemptValidity.isValid else { throw ModelDeadline.expired }
                        return try await invocation.call(frozen, onPartial: partial)
                    }
                }
            } onCancel: { attemptValidity.invalidate() }
            try Task.checkCancellation()
            try await validate()
            try await ModelValidation.current?()
            guard attemptValidity.isValid else { throw ModelDeadline.expired }
            log.emit(.callFinished, .init(stage: .service, outcome: .success, actualModel: invocation.modelID,
                durationMs: RuntimeLog.milliseconds(since: started), modelRole: role, attemptID: attemptID.uuidString))
            return .init(text: text, model: invocation.modelID)
        } catch {
            let code = RuntimeLog.code(error)
            log.emit(.callFinished, .init(stage: .service, outcome: code == .cancelled ? .cancelled : code == .timeout ? .timeout : .failed,
                errorCode: code, durationMs: RuntimeLog.milliseconds(since: started), modelRole: role, attemptID: attemptID.uuidString))
            throw error
        }
    }
    static func canFallback(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let failure = error as? AIProviderPlugin.Failure {
            if let status = failure.httpStatus { return status == 408 || status == 429 || (500...599).contains(status) }
            return [.timeout, .disconnected, .rateLimited].contains(failure.runtimeLogCode)
        }
        if let error = error as? URLError {
            return [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(error.code)
        }
        return false
    }
    private func acquire() async throws {
        try Task.checkCancellation()
        if !busy { busy = true; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiters.append((id, $0)) }
        } onCancel: { Task { await self.cancel(id) } }
    }
    private func cancel(_ id: UUID) {
        if let index = waiters.firstIndex(where: { $0.0 == id }) {
            waiters.remove(at: index).1.resume(throwing: CancellationError())
        }
    }
    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().1.resume() }
    }
}
