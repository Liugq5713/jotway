import Foundation

struct RouteInput: Sendable {
    let draft: RecordDraft
    let actions: [ActionDescriptor]
    let userRules: [IntentRule]
    let explicitTargetID: String?
    let recognizedTargetID: String?
    let recognitionIsCurrent: Bool
    let defaultActionID: String?
    let applicationIDs: Set<String>
    var setupActions: [ActionDescriptor] = []
    var defaultSetupActionID: String? = nil
}

enum RouteFailure: Equatable, Sendable {
    case targetUnavailable(String)
    case noDefaultAction
}

enum RouteSource: Equatable, Sendable {
    case explicit
    case userRule
    case localKeyword
    case recognition
    case fallback
}

enum RouteDecision: Equatable, Sendable {
    case action(String, source: RouteSource)
    case setup(String, source: RouteSource)
    case application(String, source: RouteSource)
    case unavailable(RouteFailure, source: RouteSource)
    case empty

    var targetID: String? {
        switch self {
        case .action(let id, _), .setup(let id, _), .application(let id, _): id
        case .unavailable(.targetUnavailable(let id), _): id
        case .unavailable(.noDefaultAction, _), .empty: nil
        }
    }

    var source: RouteSource? {
        switch self {
        case .action(_, let source), .setup(_, let source), .application(_, let source), .unavailable(_, let source): source
        case .empty: nil
        }
    }
}

/// Launcher 唯一的路由优先级实现；只消费值类型，不依赖 UI、数据库或网络。
struct RouteResolver: Sendable {
    func resolve(_ input: RouteInput) -> RouteDecision {
        let text = input.draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }

        let actionIDs = Set(input.actions.map(\.id))
        let setupIDs = Set(input.setupActions.map(\.id))
        func target(_ id: String, source: RouteSource) -> RouteDecision {
            if actionIDs.contains(id) { return .action(id, source: source) }
            if setupIDs.contains(id) { return .setup(id, source: source) }
            if input.applicationIDs.contains(id) { return .application(id, source: source) }
            return .unavailable(.targetUnavailable(id), source: source)
        }

        if let explicit = input.explicitTargetID { return target(explicit, source: .explicit) }

        let lowercased = text.lowercased()
        if let rule = input.userRules.first(where: {
            let phrase = $0.phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !phrase.isEmpty && lowercased.hasPrefix(phrase)
        }) {
            return target(rule.actionID, source: .userRule)
        }

        if let action = (input.actions + input.setupActions).first(where: { descriptor in
            descriptor.intentHints.localKeywords.contains { Self.matchesLocalPrefix($0, in: lowercased) }
        }) {
            return target(action.id, source: .localKeyword)
        }

        if input.recognitionIsCurrent, let recognized = input.recognizedTargetID,
           actionIDs.contains(recognized) || input.applicationIDs.contains(recognized) {
            return target(recognized, source: .recognition)
        }

        if let defaultActionID = input.defaultActionID,
           input.actions.contains(where: { $0.id == defaultActionID }) {
            return .action(defaultActionID, source: .fallback)
        }
        if let defaultID = input.defaultSetupActionID, setupIDs.contains(defaultID) {
            return .setup(defaultID, source: .fallback)
        }
        return .unavailable(.noDefaultAction, source: .fallback)
    }

    /// English prefixes require a token boundary so a longer word cannot produce a false match.
    /// Existing CJK prefixes retain their established behavior.
    static func matchesLocalPrefix(_ prefix: String, in text: String) -> Bool {
        guard let range = text.range(of: prefix, options: [.anchored, .caseInsensitive]) else { return false }
        guard range.upperBound != text.endIndex else { return true }
        // A delimiter included in the prefix already supplies the token boundary (e.g. "ChatGPT:").
        if let last = prefix.last, last.isWhitespace || last.unicodeScalars.allSatisfy({
            CharacterSet.punctuationCharacters.contains($0)
        }) { return true }
        let isEnglish = !prefix.unicodeScalars.contains {
            CharacterSet.letters.contains($0) && !$0.isASCII
        } && prefix.unicodeScalars.contains(where: CharacterSet.letters.contains)
        guard isEnglish else { return true }
        let next = text[range.upperBound]
        return next.isWhitespace || next.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0)
        }
    }
}
