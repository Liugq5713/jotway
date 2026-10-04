import CryptoKit
import Foundation

enum OperationExecutionOutcome: String, Codable, Sendable { case created, opened, prefilled, accepted, failed, unknown }
enum OperationCompleteness: String, Codable, Sendable { case complete; case legacyPartial = "legacy_partial" }
enum OperationTargetKind: String, Codable, Sendable { case action, application, setup, unknown }
enum OperationRouteSource: String, Codable, Sendable {
    case explicit, model, fallback
    case userRule = "user_rule", localKeyword = "local_keyword", localApplication = "local_application"
}
enum OperationSelectionOrigin: String, Codable, Sendable { case userChoice = "user_choice", setupCompletion = "setup_completion", automatic }
enum OperationSelectionMode: String, Codable, Sendable { case explicit, automatic }
enum OperationSelectionContinuity: String, Codable, Sendable { case direct, inherited }
enum OperationConfirmationSource: String, Codable, Sendable { case enter, commandEnter = "command_enter", button }
enum OperationCaptureTrigger: String, Codable, Sendable { case stableInput = "stable_input", recognition, selection, confirmation, hide, clear }
enum OperationSelectionTrigger: String, Codable, Sendable { case keyboard, button, setupCompletion = "setup_completion" }
enum OperationTextTransform: String, Codable, Sendable { case unchanged, trimWhitespaceAndNewlines = "trim_whitespace_and_newlines" }
enum OperationRestoreMode: String, Codable, Sendable { case restore, merge }
enum OperationLegacySource: String, Codable, Sendable { case intentFeedback = "intent_feedback", intentCorrections = "intent_corrections" }
enum OperationEventKind: String, Codable, Sendable {
    case inputCaptured = "input_captured", panelOpened = "panel_opened", panelHidden = "panel_hidden"
    case recognitionStarted = "recognition_started", recognitionFinished = "recognition_finished"
    case routePresented = "route_presented", targetSelected = "target_selected"
    case setupStarted = "setup_started", setupFinished = "setup_finished", confirmationBlocked = "confirmation_blocked"
    case confirmRequested = "confirm_requested", submissionAccepted = "submission_accepted", submissionRejected = "submission_rejected"
    case executionFinished = "execution_finished", draftRestored = "draft_restored", draftCleared = "draft_cleared"
    case legacyObservation = "legacy_observation"
}
enum OperationEventOutcome: String, Codable, Sendable {
    case suggested, noSuggestion = "no_suggestion", failed, cancelled, stale, available, setup, unavailable, completed
    case created, opened, prefilled, accepted, unknown
}

struct OperationInput: Codable, Equatable, Sendable {
    let id: String
    let lineageID: String
    let inputVersion: Int
    let capturedAt: Int64
    let text: String
    var utf8Bytes: Int { text.utf8.count }

    init(id: String, lineageID: String, inputVersion: Int, capturedAt: Int64, text: String) {
        self.id = id
        self.lineageID = lineageID
        self.inputVersion = inputVersion
        self.capturedAt = capturedAt
        self.text = text
    }
    private enum CodingKeys: String, CodingKey { case id, lineageID, inputVersion, capturedAt, text, utf8Bytes }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        lineageID = try values.decode(String.self, forKey: .lineageID)
        inputVersion = try values.decode(Int.self, forKey: .inputVersion)
        capturedAt = try values.decode(Int64.self, forKey: .capturedAt)
        text = try values.decode(String.self, forKey: .text)
        guard try values.decode(Int.self, forKey: .utf8Bytes) == text.utf8.count else {
            throw DecodingError.dataCorruptedError(forKey: .utf8Bytes, in: values, debugDescription: "Invalid UTF-8 byte count")
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(lineageID, forKey: .lineageID)
        try values.encode(inputVersion, forKey: .inputVersion)
        try values.encode(capturedAt, forKey: .capturedAt)
        try values.encode(text, forKey: .text)
        try values.encode(utf8Bytes, forKey: .utf8Bytes)
    }
}

struct OperationRule: Codable, Equatable, Sendable {
    var phrase: String
    var targetID: String
}
struct OperationActionConfiguration: Codable, Equatable, Sendable {
    var id: String
    var localKeywords: [String] = []
    var modelBinding: String = "none"
    var modelCriteria: String? = nil
    var isEnabled: Bool = true
    var availability: String = "ready"
    var unavailableReasonCode: String? = nil
    var fallbackPriority: Int? = nil
}
struct OperationThreshold: Codable, Equatable, Sendable {
    var name: String
    var value: Double
}
struct OperationConfiguration: Codable, Equatable, Sendable {
    var localRules: [OperationRule] = []
    var actions: [OperationActionConfiguration] = []
    var defaultTargetID: String? = nil
    var recognitionEnabled: Bool = false
    var recognitionQuestion: String? = nil
    var thresholds: [OperationThreshold] = []
}
struct OperationContext: Codable, Equatable, Sendable {
    let id: String
    let capturedAt: Int64
    let schemaVersion: Int
    let completeness: OperationCompleteness
    let appVersion: String?
    let appBuild: String?
    let ruleVersion: String?
    let requestedModel: String?
    let configuration: OperationConfiguration

    init(capturedAt: Int64, completeness: OperationCompleteness = .complete,
         appVersion: String? = nil, appBuild: String? = nil, ruleVersion: String? = nil,
         requestedModel: String? = nil, configuration: OperationConfiguration = .init()) throws {
        self.capturedAt = capturedAt
        self.schemaVersion = 1
        self.completeness = completeness
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.ruleVersion = ruleVersion
        self.requestedModel = requestedModel
        self.configuration = configuration
        let value = ContextContent(schemaVersion: 1, completeness: completeness, appVersion: appVersion,
                                   appBuild: appBuild, ruleVersion: ruleVersion, requestedModel: requestedModel,
                                   configuration: configuration)
        id = "context-" + SHA256.hash(data: try operationJSON(value)).map { String(format: "%02x", $0) }.joined()
    }

    func hasSameContent(as other: OperationContext) -> Bool {
        schemaVersion == other.schemaVersion && completeness == other.completeness
            && appVersion == other.appVersion && appBuild == other.appBuild && ruleVersion == other.ruleVersion
            && requestedModel == other.requestedModel && configuration == other.configuration
    }

    private struct ContextContent: Encodable {
        let schemaVersion: Int
        let completeness: OperationCompleteness
        let appVersion: String?
        let appBuild: String?
        let ruleVersion: String?
        let requestedModel: String?
        let configuration: OperationConfiguration
    }
}

struct OperationAttempt: Codable, Equatable, Sendable {
    var id: String
    var inputID: String
    var contextID: String
    var targetKind: OperationTargetKind
    var targetID: String
    var routeSource: OperationRouteSource
    var selectionOrigin: OperationSelectionOrigin
    var confirmationSource: OperationConfirmationSource
    var decisionEventID: String? = nil
    var firstChoiceEventID: String? = nil
    var retryOfAttemptID: String? = nil
}

struct OperationCaptureDetails: Codable, Equatable, Sendable { var trigger: OperationCaptureTrigger }
struct OperationCandidate: Codable, Equatable, Sendable {
    var id: String
    var name: String? = nil
    var bundleIdentifier: String? = nil
    var rank: Int? = nil
    var score: Double? = nil
    var match: String? = nil
    var openCount: Int? = nil
    var lastOpenedAt: Int64? = nil
}
struct OperationScoredOption: Codable, Equatable, Sendable {
    var id: String
    var score: Double? = nil
    var question: String? = nil
    var confidence: Double? = nil
}
struct OperationRecognitionDetails: Codable, Equatable, Sendable {
    var actualModel: String? = nil
    var candidates: [OperationCandidate] = []
    var options: [OperationScoredOption] = []
}
struct OperationRouteDetails: Codable, Equatable, Sendable { var presentationID: String }
struct OperationSelectionDetails: Codable, Equatable, Sendable {
    var selectionOrigin: OperationSelectionOrigin
    var trigger: OperationSelectionTrigger
    var previousPresentedEventID: String? = nil
    /// Missing in earlier records, whose targetSelected events always selected an explicit target.
    var mode: OperationSelectionMode? = nil
}
struct OperationConfirmationDetails: Codable, Equatable, Sendable {
    var textTransform: OperationTextTransform = .trimWhitespaceAndNewlines
    /// An inherited choice has no newly observed click or cross-input first-choice reference.
    var selectionContinuity: OperationSelectionContinuity? = nil
}
struct OperationSubmissionDetails: Codable, Equatable, Sendable {}
struct OperationExecutionDetails: Codable, Equatable, Sendable {}
struct OperationSetupDetails: Codable, Equatable, Sendable { var setupID: String }
struct OperationPanelDetails: Codable, Equatable, Sendable { var presentationID: String }
struct OperationRestorationDetails: Codable, Equatable, Sendable {
    var sourceLineageID: String
    var sourceAttemptID: String? = nil
    var mode: OperationRestoreMode = .restore
}
struct OperationClearDetails: Codable, Equatable, Sendable {}

/// Tagged JSON preserves arbitrary historical values, including unknown enum strings and exact
/// number tokens. It is used only for legacy observations, never current routing or execution.
indirect enum OperationJSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), string(String), number(String), array([OperationJSONValue]), object([String: OperationJSONValue])
}
struct OperationLegacyDetails: Codable, Equatable, Sendable {
    var sample: OperationJSONValue? = nil
    var execution: OperationJSONValue? = nil
    var data: OperationJSONValue? = nil
    var movedTargetField: String? = nil
    var correctedAt: OperationJSONValue? = nil
    var occurredAtKnown: Bool = true
}

enum OperationDetails: Codable, Equatable, Sendable {
    case capture(OperationCaptureDetails)
    case recognition(OperationRecognitionDetails)
    case route(OperationRouteDetails)
    case selection(OperationSelectionDetails)
    case confirmation(OperationConfirmationDetails)
    case submission(OperationSubmissionDetails)
    case execution(OperationExecutionDetails)
    case setup(OperationSetupDetails)
    case panel(OperationPanelDetails)
    case restoration(OperationRestorationDetails)
    case clear(OperationClearDetails)
    case legacy(OperationLegacyDetails)
}

struct OperationEvent: Codable, Equatable, Sendable {
    var sequence: Int64? = nil
    var id: String
    var inputID: String
    var contextID: String
    var runID: String?
    var occurredAt: Int64
    var kind: OperationEventKind
    var attemptID: String? = nil
    var requestID: String? = nil
    var targetKind: OperationTargetKind? = nil
    var targetID: String? = nil
    var routeSource: OperationRouteSource? = nil
    var outcome: OperationEventOutcome? = nil
    var reasonCode: String? = nil
    var durationMS: Int64? = nil
    var detailVersion: Int = 1
    var details: OperationDetails
    var legacySource: OperationLegacySource? = nil
    var legacyID: String? = nil
}

struct OperationSnapshot: Codable, Equatable, Sendable {
    var inputs: [OperationInput]
    var contexts: [OperationContext]
    var attempts: [OperationAttempt]
    var events: [OperationEvent]
}

func operationJSON<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}
