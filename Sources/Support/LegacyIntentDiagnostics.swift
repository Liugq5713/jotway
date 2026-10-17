import Foundation

/// Compatibility schema for historical Jev diagnostics; no service or credentials are available.
struct LegacyIntentDiagnostics: Codable, Sendable, Equatable {
    typealias Source = RecognitionSource
    typealias ApplicationMatch = RecognitionApplicationMatch
    enum QuestionID: String, Codable, Sendable {
        case currentRequest = "current_request", outerOperation = "outer_operation"
        case taskScope = "task_scope", appTarget = "app_target", connectionCheck = "connection_check"
        case captureKind = "capture_kind"
    }
    enum Action: String, Codable, Sendable {
        case google, conversation, openApplication = "open_application", capture, none, unknown

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

    }
    struct Answer: Codable, Sendable, Equatable {
        let question: QuestionID
        var noul: Double? = nil
        var choice: String? = nil
        var confidence: Double? = nil
        var probabilities: [String: Double]? = nil
    }
    var ruleVersion = "jev-intent-v9"
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

    static func validModel(_ value: String, requested: Bool = false) -> Bool {
        if requested && value == "jev-latest" { return true }
        return value.utf8.count <= 80 && value.range(of: #"^jev-[0-9]+(?:\.[0-9]+){1,3}(?:-[a-z0-9]+)?$"#, options: .regularExpression) != nil
    }

    static func options(for question: QuestionID) -> Set<String> {
        switch question {
        case .currentRequest, .connectionCheck: []
        case .outerOperation: ["google_search", "open_app", "unspecified", "multiple", "unsupported", "unclear"]
        case .taskScope: ["public_web", "conversation", "other", "unclear"]
        case .captureKind: [] // Historical action IDs are checked structurally below.
        case .appTarget: Set((0..<32).map { "app_\($0)" } + ["none"])
        }
    }

    var bounded: Self {
        var value = self
        value.ruleVersion = ["jev-intent-v1", "jev-intent-v2", "jev-intent-v3", "jev-intent-v4", "jev-intent-v5", "jev-intent-v6", "jev-intent-v7", "jev-intent-v8", "jev-intent-v9", "jev-connection-v1"].contains(ruleVersion) ? ruleVersion : "unknown"
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
