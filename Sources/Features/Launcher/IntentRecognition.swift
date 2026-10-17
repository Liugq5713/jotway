import Foundation

/// 每次识别属于一个确切的会话快照；候选、选择和迟到结果校验均不依赖编辑器实例。
@MainActor
final class IntentRecognition {
    enum ConfirmationSource { case enter, commandEnter, button }
    struct Application: Equatable, Sendable {
        let id: String
        let name: String
        let url: URL
        var aliases: [String] = []
        var bundleIdentifier: String? = nil
        /// Prepared by the catalog. Synthetic callers can omit it and use names/aliases.
        var searchProfile: ApplicationSearchProfile? = nil
    }

    /// 主输入路径用的常用度信号；来自 ApplicationUsage，只带次数与时间，不带路径。
    typealias ApplicationRank = ApplicationMatcher.Usage

    struct Snapshot: Equatable, Sendable {
        let draftID: UUID
        let revision: Int
        let panelSession: Int
        let registryRevision: Int
        let text: String
        let applications: [Application]
        /// 目录应用的常用度（键为稳定 id）；只区分同质量匹配，另保留已有短前缀规则。
        var applicationRanks: [String: ApplicationRank] = [:]
        /// Full-catalog evidence frozen with the input; never infer uniqueness from the bounded list.
        var applicationEvaluation: ApplicationMatcher.Evaluation? = nil
        /// 当前启用且可用的 actions（id + 标题），由 registry 驱动——⌥↕ 候选与目标可用性的唯一来源。
        var availableActions: [ActionTarget] = []
        /// 当前真实可用的兜底 action id；无可用默认 action 时为空。
        var defaultActionID = ""
    }

    /// ⌥↕ 一个可切换目标的最小信息：稳定 id + 面向用户标题。均来自 registry。
    struct ActionTarget: Equatable, Sendable {
        let id: String
        let title: String
    }

    enum Action: Equatable, Sendable {
        case openApplication(String)
    }
    enum Rejection: String {
        case applicationPrefixTooShort = "application_prefix_too_short"
        case targetUnavailable = "target_unavailable"
    }
    struct Suggestion: Equatable {
        var id = UUID()
        let snapshot: Snapshot
        let action: Action
        let recognition: RecognitionSummary
        var targetID: String { switch action { case .openApplication(let id): id } }
        var title: String {
            L10n.text("launcher.open_application",
                snapshot.applications.first { $0.id == targetID }?.name ?? L10n.text("launcher.application"))
        }
    }
    private let isCurrent: @MainActor (Snapshot) -> Bool
    private let changed: @MainActor () -> Void
    private let evaluated: @MainActor (Snapshot, RecognitionSummary, Action?, String?) -> Void
    private(set) var snapshot: Snapshot?
    private(set) var suggestion: Suggestion?
    private var dismissed: Snapshot?

    init(isCurrent: @escaping @MainActor (Snapshot) -> Bool,
         changed: @escaping @MainActor () -> Void = {},
         evaluated: @escaping @MainActor (Snapshot, RecognitionSummary, Action?, String?) -> Void = { _, _, _, _ in }) {
        self.isCurrent = isCurrent; self.changed = changed; self.evaluated = evaluated
    }
    func update(_ next: Snapshot?) {
        guard next != snapshot else { return }
        snapshot = next; suggestion = nil
        guard let next, isCurrent(next) else { changed(); return }
        if let dismissed, next.draftID == dismissed.draftID,
           next.revision == dismissed.revision, next.panelSession == dismissed.panelSession {
            changed(); return
        }
        if let local = Self.localApplicationMatch(in: next.text, applications: next.applications,
            ranks: next.applicationRanks, evaluation: next.applicationEvaluation) {
            let summary = RecognitionSummary(source: .localAppName, requestID: UUID(), ruleVersion: nil,
                                             actualModel: nil, applicationMatch: local.kind)
            let action = local.rejection == nil ? local.applications.first.map { Action.openApplication($0.id) } : nil
            if let action { suggestion = .init(snapshot: next, action: action, recognition: summary) }
            evaluated(next, summary, action, local.rejection?.rawValue)
        }
        changed()
    }
    func dismiss() { dismissed = snapshot; suggestion = nil; changed() }
    func finishSuggestion(confirmed: Bool) -> Suggestion? {
        guard let value = suggestion, value.snapshot == snapshot, isCurrent(value.snapshot) else {
            suggestion = nil; changed(); return nil
        }
        dismissed = value.snapshot; suggestion = nil; changed(); return value
    }

    static func localApplicationMatch(in text: String, applications: [Application],
                                      ranks: [String: ApplicationRank] = [:],
                                      evaluation: ApplicationMatcher.Evaluation? = nil)
        -> (kind: RecognitionApplicationMatch, applications: [Application], rejection: Rejection?)? {
        guard text.utf8.count <= ApplicationMatcher.maximumTextBytes else { return nil }
        let result = evaluation ?? ApplicationMatcher.evaluate(text, candidates: applications.map {
            .init(id: $0.id, profile: $0.searchProfile ?? ApplicationSearchProfile(names: [$0.name] + $0.aliases))
        }, usage: ranks)
        let kind = result.matches.first.map { RecognitionApplicationMatch(rawValue: $0.kind.rawValue) ?? .unknown } ?? .prefix
        switch result.resolution {
        case .notApplicable, .noMatch: return nil
        case .tooShort: return (kind, [], .applicationPrefixTooShort)
        case .selected(let match):
            guard let application = applications.first(where: { $0.id == match.id }) else {
                return (kind, [], .targetUnavailable)
            }
            return (kind, [application], nil)
        }
    }

    static func application(_ installed: InstalledApplication) -> Application {
        Application(id: installed.launcherID, name: installed.name, url: installed.url,
                    aliases: installed.searchNames, bundleIdentifier: installed.bundleIdentifier,
                    searchProfile: installed.searchProfile)
    }
}
