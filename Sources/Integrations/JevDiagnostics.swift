import Foundation
import os

/// Only bounded diagnostics cross into RuntimeLog. No text, credentials, paths or raw responses.
struct JevDiagnostics: Codable, Sendable, Equatable {
    enum Source: String, Codable, Sendable { case model, localAppName = "local_app_name" }
    enum ApplicationMatch: String, Codable, Sendable { case exact, prefix }
    enum QuestionID: String, Codable, Sendable {
        case currentRequest = "current_request", outerOperation = "outer_operation"
        case taskScope = "task_scope", appTarget = "app_target", connectionCheck = "connection_check"
        case captureKind = "capture_kind"
    }
    enum Action: String, Codable, Sendable {
        case google, openApplication = "open_application", capture, none, unknown

        init(from decoder: Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(String.self)
            self = Self(rawValue: rawValue) ?? .unknown
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }
    enum Reason: String, Codable, Sendable {
        case evaluated, presented, confirmed, dismissed, cancelled, stale
        case missingKey = "missing_key", configurationBlocked = "configuration_blocked"
        case credentialStorage = "credential_storage"
        case inputTooLarge = "input_too_large", emptyInput = "empty_input", invalidCandidates = "invalid_candidates"
        case authentication, rateLimited = "rate_limited", disconnected, timeout, http, format
        case currentRequestThreshold = "current_request_threshold", choiceConfidence = "choice_confidence"
        case choiceProbability = "choice_probability", multiple, unsupported, unclear, outsideScope = "outside_scope"
        case noUniqueApplication = "no_unique_application"
        case targetUnavailable = "target_unavailable"
        case applicationPrefixTooShort = "application_prefix_too_short"
        case unknown

        init(from decoder: Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(String.self)
            self = Self(rawValue: rawValue) ?? .unknown
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        var userMessage: String? {
            switch self {
            case .missingKey: L10n.text("jev.error.missing_key")
            case .configurationBlocked, .invalidCandidates: L10n.text("jev.error.configuration")
            case .credentialStorage: L10n.text("jev.error.credential_storage")
            case .authentication: L10n.text("jev.error.authentication")
            case .rateLimited: L10n.text("jev.error.rate_limited")
            case .disconnected: L10n.text("jev.error.disconnected")
            case .timeout: L10n.text("jev.error.timeout")
            case .http: L10n.text("jev.error.http")
            case .format: L10n.text("jev.error.format")
            default: nil
            }
        }
    }
    struct Answer: Codable, Sendable, Equatable {
        let question: QuestionID
        var noul: Double? = nil
        var choice: String? = nil
        var confidence: Double? = nil
        var probabilities: [String: Double]? = nil
    }
    var ruleVersion = Jev.ruleVersion
    var decisionSource: Source = .model
    var applicationMatch: ApplicationMatch? = nil
    var draftRevision: Int? = nil
    var candidateCount = 0
    var applicationIDs: [String] = []
    var httpAttempted = false
    var answers: [Answer] = []
    var consumedQuestions: [QuestionID] = []
    var decisiveQuestion: QuestionID? = nil
    var currentRequestThreshold: Double? = nil
    var confidenceThreshold: Double? = nil
    var probabilityThreshold: Double? = nil
    var modelAction: Action? = nil
    var suggestedAction: Action? = nil
    var reason: Reason? = nil

    static func failureReason(_ error: Error) -> Reason {
        if error is CancellationError { return .cancelled }
        if let failure = error as? Jev.Failure { return failure.diagnosticReason }
        if error is APIKeyStore.Failure { return .credentialStorage }
        if let failure = error as? URLError {
            return failure.code == .cancelled ? .cancelled : failure.code == .timedOut ? .timeout : .disconnected
        }
        return .configurationBlocked
    }

    static func validModel(_ value: String, requested: Bool = false) -> Bool {
        if requested && value == "jev-latest" { return true }
        return value.utf8.count <= 80 && value.range(of: #"^jev-[0-9]+(?:\.[0-9]+){1,3}(?:-[a-z0-9]+)?$"#, options: .regularExpression) != nil
    }

    static func options(for question: QuestionID) -> Set<String> {
        switch question {
        case .currentRequest, .connectionCheck: []
        case .outerOperation: ["google_search", "open_app", "unspecified", "multiple", "unsupported", "unclear"]
        case .taskScope: ["public_web", "other", "unclear"]
        case .captureKind: [] // 动态：合法选项是运行时注入的 action id，见 Jev.evaluate 与 bounded。
        case .appTarget: Set((0..<32).map { "app_\($0)" } + ["none"])
        }
    }

    var bounded: Self {
        var value = self
        value.ruleVersion = ["jev-intent-v1", "jev-intent-v2", "jev-intent-v3", "jev-intent-v4", "jev-intent-v5", "jev-intent-v6", "jev-intent-v7", Jev.ruleVersion, "jev-connection-v1"].contains(ruleVersion) ? ruleVersion : "unknown"
        value.draftRevision = draftRevision.flatMap { $0 >= 0 ? $0 : nil }
        value.candidateCount = min(10_000, max(0, candidateCount))
        value.applicationIDs = Array(applicationIDs.filter {
            $0.range(of: #"^app_[a-f0-9]{16}$"#, options: .regularExpression) != nil
        }.prefix(32))
        func probability(_ number: Double?) -> Double? { number.flatMap { $0.isFinite && (0...1).contains($0) ? $0 : nil } }
        value.currentRequestThreshold = probability(currentRequestThreshold)
        value.confidenceThreshold = probability(confidenceThreshold)
        value.probabilityThreshold = probability(probabilityThreshold)
        var seen = Set<QuestionID>()
        value.answers = answers.filter { answer in
            guard seen.insert(answer.question).inserted else { return false }
            if [.currentRequest, .connectionCheck].contains(answer.question) {
                return probability(answer.noul) != nil && answer.choice == nil && answer.confidence == nil && answer.probabilities == nil
            }
            let options = Self.options(for: answer.question)
            // capture_kind 的合法选项动态（action id），此处无从核对固定集——只校验结构与数值自洽。
            let dynamicOptions = answer.question == .captureKind
            guard answer.noul == nil, let choice = answer.choice, dynamicOptions || options.contains(choice),
                  probability(answer.confidence) != nil, let probabilities = answer.probabilities,
                  !probabilities.isEmpty, probabilities.count <= 33,
                  dynamicOptions || Set(probabilities.keys).isSubset(of: options),
                  probabilities.values.allSatisfy({ probability($0) != nil }),
                  let selected = probabilities[choice], let maximum = probabilities.values.max() else { return false }
            return abs(probabilities.values.reduce(0, +) - 1) <= 0.00001 && selected + 0.000001 >= maximum
        }
        value.consumedQuestions = Array(Set(consumedQuestions)).sorted { $0.rawValue < $1.rawValue }
        if decisionSource == .localAppName {
            value.answers = []; value.consumedQuestions = []; value.decisiveQuestion = nil; value.httpAttempted = false
            value.currentRequestThreshold = nil; value.confidenceThreshold = nil; value.probabilityThreshold = nil
            value.modelAction = nil
        } else { value.applicationMatch = nil }
        return value
    }
}

/// A cancellation closes an attempt synchronously, even when the transport ignores cancellation.
final class JevTrace: @unchecked Sendable {
    @TaskLocal static var current: JevTrace?
    private struct State {
        var finished = false
        var fields: RuntimeLog.Fields
    }
    let context: RuntimeLog.Context
    private let state: OSAllocatedUnfairLock<State>

    init(log: RuntimeLog = .shared, purpose: RuntimeLog.Purpose = .intentRecognition,
         draftID: UUID? = nil, revision: Int? = nil, candidateIDs: [String] = [], bytes: Int = 0,
         started: UInt64 = RuntimeLog.ticks(), source: JevDiagnostics.Source = .model,
         applicationMatch: JevDiagnostics.ApplicationMatch? = nil) {
        context = RuntimeLog.Context(log: log, module: .intent, draftID: draftID, provider: "jev",
            purpose: purpose, operation: .recognize, started: started)
        let diagnostic = JevDiagnostics(ruleVersion: purpose == .connectionTest ? "jev-connection-v1" : Jev.ruleVersion,
            decisionSource: source, applicationMatch: applicationMatch,
            draftRevision: revision, candidateCount: candidateIDs.count, applicationIDs: candidateIDs)
        let fields = RuntimeLog.Fields(requestedModel: source == .model ? Jev.model : nil,
            actualModel: source == .model ? "unknown" : nil, queueDurationMs: RuntimeLog.milliseconds(since: started),
            bytes: purpose == .connectionTest ? Jev.connectionTestText.utf8.count : bytes, intent: diagnostic)
        state = OSAllocatedUnfairLock(initialState: State(fields: fields))
        context.emit(.requestStarted, fields)
    }

    func update(_ body: @Sendable (inout RuntimeLog.Fields) -> Void) {
        state.withLock { if !$0.finished { body(&$0.fields) } }
    }

    func httpStarted() {
        state.withLock {
            guard !$0.finished else { return }
            $0.fields.intent?.httpAttempted = true
            context.emit(.callStarted, $0.fields)
        }
    }

    func httpFinished(status: Int?, milliseconds: Int) {
        state.withLock {
            guard !$0.finished else { return }
            $0.fields.httpStatus = status
            $0.fields.durationMs = milliseconds
            context.emit(.callFinished, $0.fields)
        }
    }

    func finish(_ reason: JevDiagnostics.Reason, outcome: RuntimeLog.Outcome = .success,
                action: JevDiagnostics.Action? = nil, errorCode: RuntimeLog.Code? = nil) {
        state.withLock {
            guard !$0.finished else { return }
            $0.finished = true
            $0.fields.intent?.reason = reason
            $0.fields.intent?.suggestedAction = action
            $0.fields.outcome = outcome
            $0.fields.errorCode = errorCode
            context.emit(.requestFinished, $0.fields)
        }
    }

    func failed(_ error: Error) {
        let reason = JevDiagnostics.failureReason(error)
        finish(reason, outcome: reason == .cancelled ? .cancelled : reason == .timeout ? .timeout : .failed,
               errorCode: RuntimeLog.code(error))
    }

    var decisionReason: JevDiagnostics.Reason {
        state.withLock { $0.fields.intent?.reason ?? .outsideScope }
    }

    var feedbackRecognition: IntentFeedback.Recognition {
        state.withLock {
            let source = $0.fields.intent?.decisionSource ?? .model
            let model = $0.fields.actualModel
            return .init(source: source, requestID: context.requestID, ruleVersion: $0.fields.intent?.ruleVersion,
                actualModel: source == .model ? model.flatMap { JevDiagnostics.validModel($0) ? $0 : nil } : nil,
                applicationMatch: source == .localAppName ? $0.fields.intent?.applicationMatch : nil)
        }
    }

    /// Subsequent UI changes are events, not a second terminal result for the completed request.
    func presentationChanged(_ reason: JevDiagnostics.Reason) {
        state.withLock {
            var fields = $0.fields
            fields.intent?.reason = reason
            fields.outcome = nil
            fields.durationMs = nil
            context.emit(.suggestionChanged, fields)
        }
    }
}

extension Jev.Action {
    var diagnosticAction: JevDiagnostics.Action {
        switch self {
        case .google: .google
        case .capture: .capture
        }
    }
}

extension IntentRecognition.Action {
    var diagnosticAction: JevDiagnostics.Action {
        switch self {
        case .action(_, let diagnostic): diagnostic
        case .openApplication: .openApplication
        }
    }
}

extension Jev.Failure: RuntimeLogError {
    var diagnosticReason: JevDiagnostics.Reason {
        switch self {
        case .invalidAPIKey: .missingKey
        case .inputTooLong: .inputTooLarge
        case .invalidResponse, .responseTooLarge: .format
        case .timeout: .timeout
        case .disconnected: .disconnected
        case .httpStatus(401, _), .httpStatus(403, _): .authentication
        case .httpStatus(429, _), .httpStatus(529, _): .rateLimited
        case .httpStatus(422, _): .configurationBlocked
        case .httpStatus: .http
        }
    }

    var runtimeLogCode: RuntimeLog.Code {
        switch diagnosticReason {
        case .missingKey, .credentialStorage, .configurationBlocked: .configuration
        case .inputTooLarge: .inputTooLarge
        case .invalidCandidates: .validation
        case .format: .format
        case .timeout: .timeout
        case .disconnected: .disconnected
        case .authentication: .authentication
        case .rateLimited: .rateLimited
        default: .http
        }
    }
}
