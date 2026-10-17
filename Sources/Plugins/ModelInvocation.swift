import Foundation
import os

/// Only caller-owned text and constraints cross this boundary; credentials stay in frozen closures.
struct ModelTextRequest: Codable, Sendable {
    enum OutputFormat: String, Codable, Sendable { case plain, json }
    let instructions: String
    let content: String
    var outputFormat: OutputFormat = .plain
    var maximumTokens: Int? = nil
    var maximumTokensForThinkingModel: Int? = nil
    var maximumBytes = 512_000
    var timeout: TimeInterval = 300
    var streaming = false
    // Local delivery options and limits are not part of prompt-size encoding.
    enum CodingKeys: String, CodingKey { case instructions, content, outputFormat, maximumTokens, maximumTokensForThinkingModel }
}

/// Provisional text is usable only while this exact attempt remains active.
struct ModelStreamEvent: Sendable {
    enum Kind: Sendable { case attemptStarted, content(String) }
    let kind: Kind
    let invocationID: UUID
    let attemptID: UUID
    let role: RuntimeLog.ModelRole
    private let validity: ModelStreamValidity

    /// Read again on the receiving actor, including when a pending update is published later.
    var isValid: Bool { validity.isValid }

    init(kind: Kind, invocationID: UUID, attemptID: UUID, role: RuntimeLog.ModelRole,
         validity: ModelStreamValidity) {
        self.kind = kind; self.invocationID = invocationID; self.attemptID = attemptID
        self.role = role; self.validity = validity
    }
}

/// Synchronous revocation also protects work already queued on another actor.
final class ModelStreamValidity: Sendable {
    private let active = OSAllocatedUnfairLock(initialState: true)
    private let deadline: ContinuousClock.Instant?
    private let parent: ModelStreamValidity?

    init(deadline: ContinuousClock.Instant?, parent: ModelStreamValidity? = nil) {
        self.deadline = deadline; self.parent = parent
    }
    var isValid: Bool {
        !Task.isCancelled && (deadline.map { ContinuousClock.now < $0 } ?? true) && active.withLock { $0 }
            && (parent?.isValid ?? true)
    }
    func invalidate() { active.withLock { $0 = false } }
}

struct ModelTextInvocation: Sendable {
    typealias PartialHandler = @Sendable (String) async throws -> Void
    typealias EventHandler = @Sendable (ModelStreamEvent) async throws -> Void
    var maximumBytes = 512_000
    var requestTimeout: TimeInterval = 300
    var outputFormat: ModelTextRequest.OutputFormat = .plain
    var maximumTokens: Int? = nil
    var maximumTokensForThinkingModel: Int? = nil
    let version: String
    var capability: ModelConfiguration.Capability? = nil
    var providerID: String? = nil
    var expectedModelID: String? = nil
    private let generate: @Sendable (ModelTextRequest, PartialHandler?, EventHandler?) async throws -> String
    private let observedModel: @Sendable () -> String?
    var modelID: String? { observedModel() }

    init(version: String, modelID: @escaping @Sendable () -> String? = { nil },
         generate: @escaping @Sendable (ModelTextRequest, PartialHandler?) async throws -> String) {
        self.init(version: version, modelID: modelID, generateWithEvents: { request, partial, onEvent in
            guard let onEvent else { return try await generate(request, partial) }
            guard request.timeout > 0 else { throw ModelDeadline.expired }
            let deadline = request.timeout.isFinite ? ContinuousClock.now.advanced(by: .seconds(request.timeout)) : nil
            let validity = ModelStreamValidity(deadline: deadline)
            let invocationID = UUID(), attemptID = UUID()
            let validate = ModelValidation.current
            let publish: @Sendable (ModelStreamEvent.Kind) async throws -> Void = { kind in
                guard validity.isValid else { return }
                do {
                    try Task.checkCancellation()
                    try await validate?()
                    guard validity.isValid else { return }
                    try await onEvent(.init(kind: kind, invocationID: invocationID, attemptID: attemptID,
                                            role: .primary, validity: validity))
                } catch { validity.invalidate(); throw error }
            }
            return try await withTaskCancellationHandler {
                defer { validity.invalidate() }
                try await publish(.attemptStarted)
                try Task.checkCancellation()
                guard validity.isValid else { throw ModelDeadline.expired }
                let output = try await generate(request, { text in
                    guard validity.isValid else { return }
                    try await publish(.content(text))
                    guard validity.isValid else { return }
                    try await partial?(text)
                })
                try Task.checkCancellation()
                try await validate?()
                guard validity.isValid else { throw ModelDeadline.expired }
                return output
            } onCancel: { validity.invalidate() }
        })
    }

    init(version: String, modelID: @escaping @Sendable () -> String? = { nil },
         generateWithEvents: @escaping @Sendable (ModelTextRequest, PartialHandler?, EventHandler?) async throws -> String) {
        self.version = version
        self.observedModel = modelID
        self.generate = generateWithEvents
    }

    func request(_ content: String, _ instructions: String) -> ModelTextRequest {
        .init(instructions: instructions, content: content, outputFormat: outputFormat,
              maximumTokens: maximumTokens, maximumTokensForThinkingModel: maximumTokensForThinkingModel, maximumBytes: maximumBytes, timeout: requestTimeout)
    }

    func callAsFunction(_ content: String, _ instructions: String,
                        loggingPurpose: RuntimeLog.Purpose? = nil,
                        onPartial: PartialHandler? = nil) async throws -> String {
        try await call(request(content, instructions), loggingPurpose: loggingPurpose, onPartial: onPartial)
    }

    @_disfavoredOverload
    func callAsFunction(_ content: String, _ instructions: String,
                        loggingPurpose: RuntimeLog.Purpose? = nil,
                        onEvent: EventHandler?, onPartial: PartialHandler? = nil) async throws -> String {
        try await call(request(content, instructions), loggingPurpose: loggingPurpose, onEvent: onEvent, onPartial: onPartial)
    }

    func call(_ request: ModelTextRequest, loggingPurpose: RuntimeLog.Purpose? = nil,
              onPartial: PartialHandler? = nil) async throws -> String {
        try await call(request, loggingPurpose: loggingPurpose, onEvent: nil, onPartial: onPartial)
    }

    // Keep unlabelled trailing closures bound to the original String callback.
    @_disfavoredOverload
    func call(_ request: ModelTextRequest, loggingPurpose: RuntimeLog.Purpose? = nil,
              onEvent: EventHandler?, onPartial: PartialHandler? = nil) async throws -> String {
        try Task.checkCancellation()
        var log = RuntimeLog.current ?? RuntimeLog.Context()
        log.callID = log.callID ?? UUID(); log.started = RuntimeLog.ticks()
        if let loggingPurpose { log.purpose = loggingPurpose }
        log.capability = capability
        log.provider = providerID
        let result = try await RuntimeLog.$current.withValue(log) { try await generate(request, onPartial, onEvent) }
        try Task.checkCancellation()
        return result
    }

    @MainActor
    static func direct(_ configuration: AIProviderPlugin.Configuration,
                       validate: @escaping @Sendable () async throws -> Void = { try Task.checkCancellation() }) throws -> Self {
        let guarded = AIProviderPlugin.Configuration(version: configuration.version,
            modelID: configuration.modelID, providerID: configuration.providerID) { request in
                try await validate()
                return try await configuration.perform(request)
            }
        // A separate actor per snapshot/flow, never a shared global execution queue.
        let generator = try AIProviderPlugin(configuration: { guarded }).generator()
        var invocation = Self(version: configuration.version, modelID: { generator.modelID }) { request, partial in
            var input = AIProviderPlugin.Request(instructions: request.instructions, content: request.content)
            input.maximumBytes = request.maximumBytes; input.timeout = request.timeout
            input.outputFormat = request.outputFormat; input.maximumTokens = request.maximumTokens
            input.maximumTokensForThinkingModel = request.maximumTokensForThinkingModel
            input.streaming = request.streaming
            if let partial {
                let inherited = ModelValidation.current
                input.onPartial = { text in
                    try Task.checkCancellation()
                    try await validate()
                    try await inherited?()
                    try await partial(text)
                }
            }
            return try await generator.perform(input)
        }
        invocation.providerID = configuration.providerID
        invocation.expectedModelID = configuration.modelID
        return invocation
    }
}

/// Opt-in diagnostics carry no authorization headers. Receivers cannot fail a model call.
struct ModelDiagnostics: Sendable {
    @TaskLocal static var current: Self?
    let request: @Sendable (Data, String, String, URL) async -> Void
    let response: @Sendable (String, String?, Bool) async -> Void
}

extension ModelTextInvocation {
    func validating(_ validate: @escaping @Sendable () async throws -> Void) -> Self {
        var result = Self(version: version, modelID: observedModel, generateWithEvents: { request, partial, event in
            try await validate()
            let inherited = ModelValidation.current
            return try await ModelValidation.$current.withValue({
                try Task.checkCancellation()
                try await inherited?()
                try await validate()
            }) {
                let result = try await self.call(request, onEvent: event, onPartial: partial)
                try await validate()
                return result
            }
        })
        result.maximumBytes = maximumBytes
        result.requestTimeout = requestTimeout
        result.outputFormat = outputFormat
        result.maximumTokens = maximumTokens
        result.maximumTokensForThinkingModel = maximumTokensForThinkingModel
        result.capability = capability
        result.providerID = providerID
        result.expectedModelID = expectedModelID
        return result
    }
}

extension ModelConfiguration {
    /// Capture configuration errors too: an accepted save must not change service later.
    func frozenText(_ capability: Capability) -> ModelTextInvocation {
        do { return try text(capability) }
        catch { return .init(version: version(capability)) { _, _ in throw error } }
    }
}

/// Business validity travels through the frozen model chain and is checked before each attempt.
enum ModelValidation {
    @TaskLocal static var current: (@Sendable () async throws -> Void)?
}
