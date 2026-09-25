import Foundation
import CryptoKit

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
        /// 目录扫描时预计算的拼音/首字母检索词；与发现的名称一样只在本机参与匹配。
        var matchTerms: [String] = []
    }

    /// 主输入路径用的常用度信号；来自 ApplicationUsage，只带次数与时间，不带路径。
    struct ApplicationRank: Equatable, Sendable {
        var openCount: Int
        var lastOpenedAt: Date
    }

    struct Snapshot: Equatable, Sendable {
        let draftID: UUID
        let revision: Int
        let panelSession: Int
        let configuration: UUID
        let registryRevision: Int
        let text: String
        let applications: [Application]
        /// 候选应用的常用度（键为候选稳定 id）；为空时前缀判定维持原长度/唯一性规则。
        var applicationRanks: [String: ApplicationRank] = [:]
        /// 当前启用且可用的 actions（id + 标题），由 registry 驱动——⌥↕ 候选与目标可用性的唯一来源。
        var availableActions: [ActionTarget] = []
        /// 当前真实可用的兜底 action id；无可用默认 action 时为空。
        var defaultActionID = ""
        /// 喂给 jev capture_kind 的存储 action 选项（id + criteria）；由输入层从 registry 组装。
        var captureOptions: [Jev.CaptureOption] = []
        /// 当前快照里声明 webSearch 绑定的 action；Jev 的 google 只能映射到此 ID。
        var webSearchActionID: String?
    }

    /// ⌥↕ 一个可切换目标的最小信息：稳定 id + 面向用户标题。均来自 registry。
    struct ActionTarget: Equatable, Sendable {
        let id: String
        let title: String
    }

    /// Local routing includes application launch; the model can only return Jev.Action.
    enum Action: Equatable, Sendable {
        case action(String, diagnostic: JevDiagnostics.Action)
        case openApplication(String)
    }

    struct Suggestion: Equatable {
        var id = UUID()
        let snapshot: Snapshot
        let action: Action
        let recognition: IntentFeedback.Recognition

        var title: String {
            switch action {
            case .openApplication(let id):
                L10n.text("launcher.open_application",
                          snapshot.applications.first { $0.id == id }?.name ?? L10n.text("launcher.application"))
            case .action(let id, _): snapshot.availableActions.first { $0.id == id }?.title ?? id
            }
        }
        var targetID: String {
            switch action {
            case .action(let id, _): id
            case .openApplication(let id): id
            }
        }
    }

    typealias Recognize = @MainActor (String, String, [Jev.CaptureOption]) async throws -> Jev.Decision?
    private static let maximumApplications = 32
    private let recognize: Recognize
    private let readKey: @MainActor () throws -> String?
    private let isCurrent: @MainActor (Snapshot) -> Bool
    private let changed: @MainActor () -> Void
    private let debounce: Duration
    private let log: RuntimeLog
    private var activeTrace: JevTrace?
    private var presentationTrace: JevTrace?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var snapshot: Snapshot?
    private var dismissed: Snapshot?
    private var blockedConfiguration: UUID?
    private var cooldownUntil = Date.distantPast
    private var throttleCount = 0
    private(set) var suggestion: Suggestion?
    private(set) var isRecognizing = false
    private(set) var issue: String?

    init(debounce: Duration = .milliseconds(500), log: RuntimeLog = .shared, readKey: @escaping @MainActor () throws -> String?,
         recognize: @escaping Recognize = { text, key, capture in
             try await Jev.recognize(text: text, apiKey: key, capture: capture)
         },
         isCurrent: @escaping @MainActor (Snapshot) -> Bool,
         changed: @escaping @MainActor () -> Void = {}) {
        self.debounce = debounce
        self.log = log
        self.readKey = readKey
        self.recognize = recognize
        self.isCurrent = isCurrent
        self.changed = changed
    }

    isolated deinit {
        activeTrace?.finish(.cancelled, outcome: .cancelled)
        task?.cancel()
    }

    func update(_ next: Snapshot?) {
        guard next != snapshot else { return }
        activeTrace?.finish(next == nil ? .cancelled : .stale, outcome: next == nil ? .cancelled : .discarded)
        activeTrace = nil
        presentationTrace?.presentationChanged(.stale)
        presentationTrace = nil
        task?.cancel()
        task = nil
        generation = UUID()
        snapshot = next
        suggestion = nil
        isRecognizing = false
        issue = nil
        changed()
        guard let next else { return }
        if let dismissed, next.draftID == dismissed.draftID,
           next.revision == dismissed.revision, next.panelSession == dismissed.panelSession { return }
        // 本地应用匹配是纯内存计算，排在防抖之前同步出结果；只有本地返回 nil 才建 task 走模型。
        let local = Self.localApplicationMatch(in: next.text, applications: next.applications, ranks: next.applicationRanks)
        let attempt = JevTrace(log: self.log, draftID: next.draftID, revision: next.revision,
            candidateIDs: next.applications.map(\.id), bytes: next.text.utf8.count, started: RuntimeLog.ticks(),
            source: local == nil ? .model : .localAppName, applicationMatch: local?.kind)
        self.activeTrace = attempt
        guard next.text.utf8.count <= Jev.maximumTextBytes else {
            attempt.finish(.inputTooLarge, outcome: .discarded)
            self.activeTrace = nil
            return
        }
        if let local {
            if let reason = local.rejection {
                attempt.finish(reason, outcome: .discarded)
                self.activeTrace = nil
                return
            }
            guard let application = local.applications.first else { return }
            let action = Action.openApplication(application.id)
            self.suggestion = Suggestion(snapshot: next, action: action, recognition: attempt.feedbackRecognition)
            attempt.finish(.presented, action: .openApplication)
            self.presentationTrace = attempt
            self.activeTrace = nil
            self.changed()
            return
        }
        let token = generation
        task = Task { [weak self] in
            guard let self else { return }
            var trace: JevTrace?
            defer {
                if self.generation == token {
                    self.activeTrace = nil
                    self.isRecognizing = false
                    self.task = nil
                    self.changed()
                }
            }
            do {
                try await Task.sleep(for: self.debounce)
                guard !Task.isCancelled, self.generation == token, self.isCurrent(next) else { return }
                trace = attempt
                guard next.configuration != self.blockedConfiguration else {
                    self.issue = JevDiagnostics.Reason.configurationBlocked.userMessage
                    attempt.finish(.configurationBlocked, outcome: .discarded)
                    return
                }
                let remaining = self.cooldownUntil.timeIntervalSinceNow
                if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
                guard !Task.isCancelled, self.generation == token, self.isCurrent(next) else {
                    attempt.finish(.stale, outcome: .discarded)
                    return
                }
                guard let key = try self.readKey(), !key.isEmpty else {
                    self.issue = JevDiagnostics.Reason.missingKey.userMessage
                    attempt.finish(.missingKey, outcome: .discarded)
                    return
                }
                self.isRecognizing = true
                self.changed()
                let answer = try await JevTrace.$current.withValue(attempt) {
                    try await self.recognize(next.text, key, next.captureOptions)
                }
                guard !Task.isCancelled, self.generation == token, self.isCurrent(next) else {
                    attempt.finish(.stale, outcome: .discarded)
                    return
                }
                self.throttleCount = 0
                if let answer {
                    attempt.update {
                        $0.intent?.modelAction = answer.action.diagnosticAction
                        $0.actualModel = JevDiagnostics.validModel(answer.model) ? answer.model : "unknown"
                    }
                    let actionID: String? = switch answer.action {
                    case .capture(let id): next.captureOptions.contains(where: { $0.id == id }) ? id : nil
                    case .google: next.webSearchActionID
                    }
                    guard let actionID else {
                        attempt.finish(.targetUnavailable, outcome: .discarded)
                        return
                    }
                    let action = Action.action(actionID, diagnostic: answer.action.diagnosticAction)
                    self.suggestion = Suggestion(snapshot: next, action: action, recognition: attempt.feedbackRecognition)
                    attempt.finish(.presented, action: answer.action.diagnosticAction)
                    self.presentationTrace = attempt
                } else {
                    attempt.finish(attempt.decisionReason, outcome: .discarded)
                }
            } catch {
                trace?.failed(error)
                guard !Task.isCancelled, self.generation == token, self.isCurrent(next) else { return }
                if let failure = error as? Jev.Failure {
                    if failure.statusCode == 401 || failure.statusCode == 403 || failure.statusCode == 422 {
                        self.blockedConfiguration = next.configuration
                    }
                    if failure.statusCode == 429 || failure.statusCode == 529 {
                        self.throttleCount = min(self.throttleCount + 1, 6)
                        let delay = max(failure.retryAfter ?? 0, min(60, pow(2, Double(self.throttleCount))))
                        self.cooldownUntil = Date().addingTimeInterval(delay)
                    }
                }
                self.issue = JevDiagnostics.failureReason(error).userMessage
            }
        }
    }

    func dismiss() {
        activeTrace?.finish(.dismissed, outcome: .discarded)
        activeTrace = nil
        presentationTrace?.presentationChanged(.dismissed)
        presentationTrace = nil
        dismissed = snapshot
        task?.cancel()
        task = nil
        generation = UUID()
        suggestion = nil
        isRecognizing = false
        issue = nil
        changed()
    }

    /// 结束一次建议展示。目标选择由 LauncherSession 管理；识别器只校验建议是否仍属当前快照。
    func finishSuggestion(confirmed: Bool) -> Suggestion? {
        guard let value = suggestion, value.snapshot == snapshot, isCurrent(value.snapshot) else {
            presentationTrace?.presentationChanged(.stale)
            presentationTrace = nil
            suggestion = nil
            changed()
            return nil
        }
        presentationTrace?.presentationChanged(confirmed ? .confirmed : .dismissed)
        presentationTrace = nil
        dismissed = value.snapshot
        task?.cancel()
        task = nil
        generation = UUID()
        suggestion = nil
        isRecognizing = false
        changed()
        return value
    }

    /// Nil means ordinary semantic input. A rejected local match must never fall through to the model.
    static func localApplicationMatch(in text: String, applications: [Application],
                                      ranks: [String: ApplicationRank] = [:])
        -> (kind: JevDiagnostics.ApplicationMatch, applications: [Application], rejection: JevDiagnostics.Reason?)? {
        if let local = applicationNameMatch(in: text, applications: applications, ranks: ranks) { return local }
        guard let target = launchCommandTarget(in: text) else { return nil }
        return applicationNameMatch(in: target, applications: applications, ranks: ranks)
    }

    private static func applicationNameMatch(in text: String, applications: [Application], ranks: [String: ApplicationRank])
        -> (kind: JevDiagnostics.ApplicationMatch, applications: [Application], rejection: JevDiagnostics.Reason?)? {
        guard text.rangeOfCharacter(from: .newlines) == nil else { return nil }
        let exact = exactApplications(in: text, applications: applications)
        if !exact.isEmpty { return (.exact, exact, exact.count == 1 ? nil : .noUniqueApplication) }
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.rangeOfCharacter(from: .newlines) == nil else { return nil }
        var identities = Set<URL>()
        let matches = applications.filter { application in
            (([application.name] + application.aliases).contains { hasNamePrefix($0, query: query) }
                || application.matchTerms.contains { hasTermPrefix($0, query: query) })
                && identities.insert(application.url.resolvingSymlinksInPath()).inserted
        }
        guard !matches.isEmpty else { return nil }
        // 有使用记录时按次数、最近打开时间与稳定名称顺序取胜，免除长度与唯一性门槛。
        let winner = matches.filter { (ranks[$0.id]?.openCount ?? 0) > 0 }.sorted { lhs, rhs in
            let left = ranks[lhs.id], right = ranks[rhs.id]
            if (left?.openCount ?? 0) != (right?.openCount ?? 0) {
                return (left?.openCount ?? 0) > (right?.openCount ?? 0)
            }
            if left?.lastOpenedAt != right?.lastOpenedAt {
                return (left?.lastOpenedAt ?? .distantPast) > (right?.lastOpenedAt ?? .distantPast)
            }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.url.path < rhs.url.path : order == .orderedAscending
        }.first
        if let winner { return (.prefix, [winner], nil) }
        // Count grapheme clusters with letters/digits, never UTF-8 bytes or padding punctuation.
        let characters = query.filter { $0.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) }
        let isHan = !characters.isEmpty && characters.range(of: #"^\p{Han}[\p{Han}\p{M}]*$"#, options: .regularExpression) != nil
        guard characters.count >= (isHan ? 2 : 3) else { return (.prefix, matches, .applicationPrefixTooShort) }
        return (.prefix, matches, matches.count == 1 ? nil : .noUniqueApplication)
    }

    private static func hasNamePrefix(_ name: String, query: String) -> Bool {
        name.range(of: query, options: [.anchored, .caseInsensitive]) != nil
    }

    /// 拼音/首字母检索词的前缀判定：查询照 matchedName 归一化（去空白、去撇号），只做前缀、不做子串。
    private static func hasTermPrefix(_ term: String, query: String) -> Bool {
        let query = query.filter { !$0.isWhitespace && $0 != "'" && $0 != "’" }
        return !query.isEmpty && term.range(of: query, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
    }

    static func exactApplications(in text: String, applications: [Application]) -> [Application] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var identities = Set<URL>()
        return applications.filter { application in
            ([application.name] + application.aliases).contains { $0.compare(query, options: .caseInsensitive) == .orderedSame }
                && identities.insert(application.url.resolvingSymlinksInPath()).inserted
        }
    }

    /// Discovered application names, aliases and identities are used only for local matching.
    static func applicationCandidates(in text: String, from applications: [InstalledApplication]) -> [Application] {
        let groups = Dictionary(grouping: applications, by: { $0.url.resolvingSymlinksInPath() })
        let names = groups.mapValues { group in Array(Set(group.flatMap { [$0.name] + $0.searchNames })) }
        var seen = Set<URL>()
        let unique = applications.filter { seen.insert($0.url.resolvingSymlinksInPath()).inserted }
        func candidate(_ app: InstalledApplication) -> Application {
            let digest = SHA256.hash(data: Data(app.url.resolvingSymlinksInPath().path.utf8))
            let id = "app_" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
            return Application(id: id, name: app.name, url: app.url,
                aliases: (names[app.url.resolvingSymlinksInPath()] ?? app.searchNames).sorted(),
                bundleIdentifier: app.bundleIdentifier, matchTerms: app.searchTexts)
        }
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let exact = unique.filter { app in
            (names[app.url.resolvingSymlinksInPath()] ?? []).contains { $0.compare(query, options: .caseInsensitive) == .orderedSame }
        }
        if !query.isEmpty, !exact.isEmpty { return exact.map(candidate) }
        if !query.isEmpty, query.rangeOfCharacter(from: .newlines) == nil {
            let prefixes = unique.filter { app in
                (names[app.url.resolvingSymlinksInPath()] ?? []).contains { hasNamePrefix($0, query: query) }
                    || app.searchTexts.contains { hasTermPrefix($0, query: query) }
            }
            // Keep every identity, including short/ambiguous prefixes, before the candidate limit.
            if !prefixes.isEmpty { return prefixes.map(candidate) }
        }
        if let target = launchCommandTarget(in: text),
           let local = applicationNameMatch(in: target, applications: unique.map(candidate), ranks: [:]) {
            return local.applications
        }
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let launchQueries = ["打开", "启动", "切换到", "切到", "open ", "launch ", "switch to "].compactMap { prefix in
            guard let range = normalized.range(of: prefix) else { return nil as String? }
            let query = normalized[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            return query.isEmpty ? nil : query
        }
        let matches = unique.filter { app in
            launchQueries.contains(where: app.matches) || ([app.name] + app.searchNames).contains { name in
                let name = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if name == "hi" {
                    // A short app name must match as a distinct token, not as part of ordinary words.
                    return normalized.range(of: #"(?<![a-z0-9_])hi(?![a-z0-9_])"#, options: .regularExpression) != nil
                }
                return name.count >= 2 && normalized.contains(name)
            }
        }
        guard matches.count <= maximumApplications else { return [] }
        guard Set(matches.map { $0.name.lowercased() }).count == matches.count else { return [] }
        return matches.map(candidate)
    }

    /// Parse only the first line; the remaining draft is never part of the launch query.
    static func launchCommandTarget(in text: String) -> String? {
        var command = (text.components(separatedBy: .newlines).first ?? "")
            .trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        for polite in ["请帮我", "帮我", "请", "please "] where command.hasPrefix(polite) {
            command = String(command.dropFirst(polite.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        guard let prefix = ["打开", "启动", "切换到", "切到", "open ", "launch ", "switch to "].first(where: command.hasPrefix) else { return nil }
        let target = command.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        return target.isEmpty ? nil : target
    }

    /// An open-app decision does not prove that adjacent notes can be deleted.
    static func isPureApplicationLaunch(_ text: String, application: Application,
                                        ranks: [String: ApplicationRank] = [:]) -> Bool {
        let command = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard command.rangeOfCharacter(from: .newlines) == nil else { return false }
        guard let local = localApplicationMatch(in: command, applications: [application], ranks: ranks) else { return false }
        return local.rejection == nil
    }
}
