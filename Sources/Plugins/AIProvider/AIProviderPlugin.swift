import Foundation
import CryptoKit
import os

/// 两个功能共用的文字生成入口；进入时固定配置，再串行调用所选来源。
actor AIProviderPlugin {
    enum Progress: String, Codable, Sendable { case queued, running }
    @TaskLocal static var progress: (@Sendable (Progress) async -> Void)?

    /// One immutable configuration reused throughout a logical generation.
    struct Generator: Sendable {
        var maximumBytes = 512_000
        var requestTimeout: TimeInterval = 300
        var logging = RuntimeLog.current ?? RuntimeLog.Context()
        let model: OSAllocatedUnfairLock<(id: String?, verified: Bool)>
        let perform: @Sendable (Request) async throws -> String

        var modelID: String? { model.withLock { $0.verified ? $0.id : nil } }

        func callAsFunction(_ content: String, _ fixedRules: String,
                            loggingPurpose: RuntimeLog.Purpose? = nil,
                            onPartial: (@Sendable (String) async throws -> Void)? = nil) async throws -> String {
            // Each call keeps its logical generation's frozen request identity.
            var log = logging
            log.callID = UUID() // Allocated before queueing, not evidence of an invocation.
            log.started = RuntimeLog.ticks()
            if let loggingPurpose { log.purpose = loggingPurpose }
            else if log.purpose != .connectionTest { log.purpose = .context }
            return try await RuntimeLog.$current.withValue(log) {
                log.emit(.stageStarted, .init(stage: .input))
                do { try Task.checkCancellation() }
                catch { log.failed(.input, error); throw error }
                var input = request(content, fixedRules)
                input.onPartial = onPartial
                log.emit(.stageFinished, .init(stage: .input, outcome: .success, requestedModel: input.modelID,
                    bytes: content.utf8.count + input.instructions.utf8.count))
                return try await perform(input)
            }
        }

        func request(_ content: String, _ instructions: String) -> Request {
            Request(instructions: instructions, content: content, modelID: model.withLock { $0.id },
                    maximumBytes: maximumBytes, timeout: requestTimeout)
        }

    }

    struct Source: Identifiable, Sendable {
        let id: String
        let title: String
        var models: [(id: String, title: String)] = []
        var modelPreferenceKey: String? = nil
        let detail: String
        var keyURL: URL? = nil
        var hasKey: (@MainActor @Sendable () throws -> Bool)? = nil
        var saveKey: (@MainActor @Sendable (String) throws -> Void)? = nil
        var removeKey: (@MainActor @Sendable () throws -> Void)? = nil
        let version: @Sendable (String?) -> String
        let configure: @MainActor @Sendable (String?) throws -> Configuration
    }

    /// Captured before queueing, including credentials held by the invocation closure.
    struct Configuration: Sendable {
        let version: String
        var modelID: String? = nil
        var providerID: String? = nil
        let perform: @Sendable (Request) async throws -> Response
    }

    struct Failure: LocalizedError, Sendable, RuntimeLogError {
        let message: String
        var runtimeLogCode: RuntimeLog.Code = .unknown
        var retryAfter: TimeInterval? = nil
        var httpStatus: Int? = nil
        var errorDescription: String? { message }
    }

    struct Request: Codable, Sendable {
        let instructions: String
        let content: String
        var context: String = ""
        var modelID: String? = nil
        var maximumBytes = 512_000
        var timeout: TimeInterval = 300
        var outputFormat: ModelTextRequest.OutputFormat = .plain
        var maximumTokens: Int? = nil
        var maximumTokensForThinkingModel: Int? = nil
        var streaming = false
        // Receives accumulated model text; local delivery options never enter the JSON payload.
        var onPartial: (@Sendable (String) async throws -> Void)? = nil
        // Local snapshot metadata is available to callers/tests, not duplicated into helper transport.
        enum CodingKeys: String, CodingKey { case instructions, content, modelID }
    }

    struct Response: Codable, Sendable {
        let result: String?
        let error: String?
        var modelID: String? = nil
        var failureCode: RuntimeLog.Code? = nil
    }

    private let configuration: @MainActor @Sendable () throws -> Configuration
    private var busy = false
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    init(configuration: @escaping @MainActor @Sendable () throws -> Configuration) {
        self.configuration = configuration
    }

    @MainActor
    func generate(content: String, instructions: String, loggingPurpose: RuntimeLog.Purpose? = nil) async throws -> String {
        try Task.checkCancellation()
        return try await generator()(content, instructions, loggingPurpose: loggingPurpose)
    }

    /// One logical generation can classify context before answering without switching source mid-request.
    @MainActor
    func generator() throws -> Generator {
        var log = RuntimeLog.current ?? RuntimeLog.Context()
        log.emit(.stageStarted, .init(stage: .configuration))
        let snapshot: Configuration
        do { snapshot = try configuration() }
        catch { log.failed(.configuration, error, code: .configuration); throw error }
        log.provider = snapshot.providerID
        log.emit(.stageFinished, .init(stage: .configuration, outcome: .success, requestedModel: snapshot.modelID))
        let model = OSAllocatedUnfairLock<(id: String?, verified: Bool)>(initialState:
            (snapshot.modelID, false))
        // Requested ID is frozen before queueing; actual helper metadata must still confirm it.
        return Generator(logging: log, model: model) { [self] request in
            return try await generate(request, configuration: snapshot, model: model)
        }
    }

    private func generate(_ original: Request, configuration: Configuration,
                          model: OSAllocatedUnfairLock<(id: String?, verified: Bool)>) async throws -> String {
        let log = RuntimeLog.current ?? RuntimeLog.Context(provider: configuration.providerID)
        let started = RuntimeLog.ticks()
        log.emit(.queued, .init(requestedModel: original.modelID))
        await Self.progress?(.queued)
        do { try await acquire() }
        catch {
            log.emit(.requestFinished, .init(outcome: .cancelled, errorCode: .cancelled, cancellationReason: .unknown,
                queueDurationMs: RuntimeLog.milliseconds(since: started), totalDurationMs: RuntimeLog.milliseconds(since: log.started)))
            throw error
        }
        defer { release() }
        let waited = RuntimeLog.milliseconds(since: started)
        let cancellation = log.cancellation
        let task = Task { try await self.perform(original, configuration: configuration, model: model, queuedFor: waited) }
        do {
            let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            log.emit(.requestFinished, .init(outcome: .success, queueDurationMs: waited, totalDurationMs: RuntimeLog.milliseconds(since: log.started)))
            return result
        } catch {
            let code = task.isCancelled ? RuntimeLog.Code.cancelled : RuntimeLog.code(error)
            log.emit(.requestFinished, .init(outcome: code == .cancelled ? .cancelled : code == .stale ? .discarded : code == .timeout ? .timeout : .failed,
                errorCode: code, cancellationReason: code == .cancelled ? cancellation.withLock { $0 } : nil,
                queueDurationMs: waited, totalDurationMs: RuntimeLog.milliseconds(since: log.started)))
            throw error
        }
    }

    private func perform(_ original: Request, configuration: Configuration,
                         model: OSAllocatedUnfairLock<(id: String?, verified: Bool)>, queuedFor: Int) async throws -> String {
        try Task.checkCancellation()
        var request = original
        request.modelID = model.withLock { $0.id } // Earlier substeps may have confirmed it while this call waited.
        let log = RuntimeLog.current ?? RuntimeLog.Context()
        let data = try JSONEncoder().encode(request)
        guard data.count <= min(512_000, request.maximumBytes) else {
            log.emit(.stageFinished, .init(stage: .input, outcome: .failed, errorCode: .inputTooLarge, bytes: data.count))
            throw Failure(message: L10n.text("ai.error.request_too_large"), runtimeLogCode: .inputTooLarge)
        }
        let started = RuntimeLog.ticks()
        log.emit(.callStarted, .init(stage: .service, requestedModel: request.modelID, queueDurationMs: queuedFor, bytes: data.count))
        let response: Response
        do {
            await Self.progress?(.running)
            try Task.checkCancellation()
            response = try await configuration.perform(request)
            if let raw = response.result {
                await ModelDiagnostics.current?.response(raw, response.modelID, true)
            }
            log.emit(.callFinished, .init(stage: .service, outcome: response.failureCode == nil ? .success : response.failureCode == .timeout ? .timeout : response.failureCode == .cancelled ? .cancelled : .failed,
                errorCode: response.failureCode, actualModel: response.modelID,
                durationMs: RuntimeLog.milliseconds(since: started)))
        } catch {
            let code = Task.isCancelled ? RuntimeLog.Code.cancelled : RuntimeLog.code(error)
            log.emit(.callFinished, .init(stage: .service, outcome: code == .cancelled ? .cancelled : code == .timeout ? .timeout : .failed,
                errorCode: code, durationMs: RuntimeLog.milliseconds(since: started)))
            throw error
        }
        try Task.checkCancellation()
        guard let result = response.result?.trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty else {
            log.emit(.stageFinished, .init(stage: .format, outcome: .failed, errorCode: .emptyResponse))
            throw Failure(message: response.error ?? L10n.text("ai.error.provider_empty"),
                          runtimeLogCode: response.failureCode ?? .emptyResponse)
        }
        log.emit(.stageStarted, .init(stage: .model, requestedModel: request.modelID, actualModel: response.modelID))
        do { try Self.confirmModel(response.modelID, in: model) }
        catch { log.failed(.model, error); throw error }
        log.emit(.stageFinished, .init(stage: .model, outcome: .success, actualModel: response.modelID))
        return result
    }

    private static func confirmModel(_ observed: String?, in model: OSAllocatedUnfairLock<(id: String?, verified: Bool)>) throws {
        try model.withLock { current in
            let parts = observed?.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false) ?? []
            guard let observed, parts.count == 2, parts.allSatisfy({ !$0.isEmpty }), observed.count <= 512,
                  observed.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
                  !["unknown", "default", "auto"].contains(parts[1].lowercased()) else {
                if current.id != nil {
                    throw Failure(message: L10n.text("ai.error.model_unknown"), runtimeLogCode: .modelUnknown)
                }
                return
            }
            guard current.id == nil || current.id == observed else {
                throw Failure(message: L10n.text("ai.error.model_mismatch"), runtimeLogCode: .modelMismatch)
            }
            current = (observed, true)
        }
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        guard busy else {
            busy = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiters.append((id, $0)) }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

}
