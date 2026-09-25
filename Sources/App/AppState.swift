import Foundation
import KeyboardShortcuts
import SwiftUI

/// 应用共享状态：启动器输入外壳的草稿、action 注册表、AI 配置、更新、Dock、快捷键。
/// 沉淀层（收件箱记录 / 卡片 / 待办 / 概览 / 完成 / 导出 / 处理面板）已随 LAUNCHER-01 退场。
@MainActor @Observable
final class AppState: NSObject {
    private let repository: LauncherStore
    let intentFeedback: IntentFeedbackStore
    private let preferences: UserDefaults
    var recordPanelFollowsCursor: Bool {
        didSet { preferences.set(recordPanelFollowsCursor, forKey: "recordPanelFollowsCursor") }
    }
    /// 本地持久存储是否可用（数据库打开失败时降级内存存储，并阻止意图反馈等落库）。
    var storageAvailable = true
    let actionConfiguration: ActionConfiguration
    let shortcutTrial = ShortcutTrial()
    let applicationUsageStore: ApplicationUsageStore
    let onboarding: OnboardingState
    let updateManager: UpdateManager
    var actionRegistry: ActionRegistry { actionConfiguration.registry }
    var needsFirstUsePresentation: Bool { onboarding.needsFirstUsePresentation }
    var needsCopyHint: Bool { onboarding.needsCopyHint }
    var hasSkippedFirstUse: Bool { onboarding.hasSkippedFirstUse }
    private(set) var showsInDock: Bool
    private var dockPreferenceIssueKey: String?
    var dockPreferenceIssue: String? { dockPreferenceIssueKey.map { L10n.text($0) } }
    var skipsFirstUseAtLaunch: Bool { onboarding.skipsFirstUseAtLaunch }
    var generalSettingsRequest = 0
    var gettingStartedRequest = 0
    var isTryingRecordShortcut: Bool { shortcutTrial.isTrying }
    var shortcutTrialMessage: String? { shortcutTrial.message }

    var returnToJotwayHint: String {
        showsInDock ? L10n.text("guide.return.dock") : L10n.text("guide.return.menu_only")
    }

    func recordPanelOffset(on displayID: String) -> CGPoint? {
        guard let values = preferences.dictionary(forKey: "recordPanelPositions")?[displayID] as? [Double],
              values.count == 2,
              values.allSatisfy(\.isFinite) else { return nil }
        return CGPoint(x: values[0], y: values[1])
    }

    func saveRecordPanelOffset(_ offset: CGPoint, on displayID: String) {
        guard offset.x.isFinite, offset.y.isFinite else { return }
        var positions = preferences.dictionary(forKey: "recordPanelPositions") ?? [:]
        positions[displayID] = [Double(offset.x), Double(offset.y)]
        preferences.set(positions, forKey: "recordPanelPositions")
    }

    @discardableResult
    func applyDockPreference(using apply: (NSApplication.ActivationPolicy) -> Bool = { NSApp.setActivationPolicy($0) }) -> Bool {
        let applied = apply(showsInDock ? .regular : .accessory)
        dockPreferenceIssueKey = applied ? nil : "settings.dock.apply_failed"
        return applied
    }

    func setShowsInDock(_ visible: Bool,
                        apply: (NSApplication.ActivationPolicy) -> Bool = { NSApp.setActivationPolicy($0) }) {
        guard apply(visible ? .regular : .accessory) else {
            dockPreferenceIssueKey = "settings.dock.change_failed"
            return
        }
        showsInDock = visible
        preferences.set(visible, forKey: "showsInDock")
        dockPreferenceIssueKey = nil
    }

    @discardableResult
    func beginRecordShortcutTrial(shortcut: KeyboardShortcuts.Shortcut?, issue: String?) -> Bool {
        shortcutTrial.begin(shortcut: shortcut, issue: issue)
    }

    func shortcutTrialLeftJotway() {
        shortcutTrial.leftApplication()
    }

    func canCompleteShortcutTrial(shortcut: KeyboardShortcuts.Shortcut?, fromExternalApplication: Bool) -> Bool {
        shortcutTrial.canComplete(shortcut: shortcut, fromExternalApplication: fromExternalApplication)
    }

    @discardableResult
    func completeRecordShortcutTrial(shortcut: KeyboardShortcuts.Shortcut?, fromExternalApplication: Bool, presented: Bool) -> Bool {
        shortcutTrial.complete(shortcut: shortcut, fromExternalApplication: fromExternalApplication, presented: presented)
    }

    func cancelRecordShortcutTrial() {
        shortcutTrial.cancel()
    }

    /// 首次提示和设置读取同一事实；推荐只做筛选，不写偏好或试注册。
    static func recordShortcutStatus(
        shortcut: KeyboardShortcuts.Shortcut? = KeyboardShortcuts.getShortcut(for: .recordNote),
        registrationError: Int32? = KeyboardShortcuts.registrationError(for: .recordNote),
        isTakenBySystem: Bool = KeyboardShortcuts.isTakenBySystem(.recordNote),
        macOSMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        isAvailable: @MainActor (KeyboardShortcuts.Shortcut) -> Bool = KeyboardShortcuts.isAvailableForRecommendation
    ) -> (shortcut: KeyboardShortcuts.Shortcut?, issue: String?, recommendation: KeyboardShortcuts.Shortcut?) {
        ShortcutTrial.status(shortcut: shortcut, registrationError: registrationError,
            isTakenBySystem: isTakenBySystem, macOSMajorVersion: macOSMajorVersion, isAvailable: isAvailable)
    }

    /// 点击时再检查候选，避免把展示后新增的冲突写成新的偏好。
    static func adoptRecordShortcut(
        _ shortcut: KeyboardShortcuts.Shortcut,
        isAvailable: @MainActor (KeyboardShortcuts.Shortcut) -> Bool = KeyboardShortcuts.isAvailableForRecommendation,
        save: (KeyboardShortcuts.Shortcut) -> Void = { KeyboardShortcuts.setShortcut($0, for: .recordNote) }
    ) -> String? {
        ShortcutTrial.adopt(shortcut, isAvailable: isAvailable, save: save)
    }

    private static let aiSourceKey = "plugin.ai.source"
    var aiSourceRevision: Int { preferences.integer(forKey: "plugin.ai.sourceRevision") }
    private(set) var aiSource: String
    var aiSources: [AIProviderPlugin.Source] {
        didSet { refreshAIModel(); invalidateAIConnectionTest() }
    }
    var selectedAISource: AIProviderPlugin.Source? { aiSources.first { $0.id == aiSource } }
    private(set) var aiModel: String?
    var aiSourceVersion: String {
        "\(selectedAISource?.version(aiModel) ?? "unavailable/" + aiSource):\(aiSourceRevision)"
    }
    private static let aiManualConfigurationKey = "plugin.ai.manualConfiguration"
    private(set) var aiManualConfiguration: AIProviderPlugin.ManualConfiguration
    @ObservationIgnored var onTestAIConnection: (@MainActor () async throws -> Void)?
    private(set) var isTestingAIConnection = false
    private enum AIConnectionStatus {
        case testing(String)
        case succeeded(String)
        case staleSucceeded
        case failed(String)
        case staleFailed
    }
    private var aiConnectionStatus: AIConnectionStatus?
    var aiConnectionMessage: String? {
        switch aiConnectionStatus {
        case .testing(let title): L10n.text("settings.ai.connection.testing_title", title)
        case .succeeded(let title): L10n.text("settings.ai.connection.succeeded", title)
        case .staleSucceeded: L10n.text("settings.ai.connection.stale_succeeded")
        case .failed(let error): L10n.text("settings.ai.connection.failed", error)
        case .staleFailed: L10n.text("settings.ai.connection.stale_failed")
        case nil: nil
        }
    }
    @ObservationIgnored private var aiConnectionRevision = 0

    var prepareForUpdate: (@MainActor () -> String?)? {
        get { updateManager.prepareForUpdate }
        set { updateManager.prepareForUpdate = newValue }
    }
    var updatesAvailable: Bool { updateManager.updatesAvailable }
    var canCheckForUpdates: Bool { updateManager.canCheckForUpdates }
    var automaticallyChecksForUpdates: Bool { updateManager.automaticallyChecksForUpdates }
    var availableUpdateVersion: String? { updateManager.availableUpdateVersion }
    var updateDownloadURL: URL? { updateManager.updateDownloadURL }
    var updateMessage: String? { updateManager.message }

    var currentVersion: String {
        updateManager.currentVersion
    }

    var updateMenuTitle: String {
        updateManager.menuTitle
    }

    var submissionEffect: SubmissionEffect {
        SubmissionEffect(rawValue: preferences.string(forKey: "submissionEffect") ?? "") ?? .wind
    }

    var applicationUsage: [String: ApplicationUsage] { applicationUsageStore.usage }
    var hasPendingApplicationUsage: Bool { applicationUsageStore.hasPendingChanges }
    /// 设置页只读列出用户对 Jev 的纠正记录（最新在前，仅本地）。读失败返回空。
    func recentIntentCorrections(limit: Int = IntentCorrection.retentionLimit) -> [IntentCorrection] {
        (try? repository.recentIntentCorrections(limit: limit)) ?? []
    }

    /// 用户在设置页清空全部纠正记录。
    func clearIntentCorrections() {
        try? repository.clearIntentCorrections()
    }

    init(repository: LauncherStore, preferences: UserDefaults = .standard,
         aiSources: [AIProviderPlugin.Source] = bundledAISources(),
         actionModules: (@MainActor (UserDefaults) -> [any ActionModule])? = nil) {
        self.repository = repository
        intentFeedback = IntentFeedbackStore(repository: repository)
        self.preferences = preferences
        let modules = actionModules?(preferences) ?? BundledActions.modules(preferences: preferences)
        actionConfiguration = ActionConfiguration(preferences: preferences, modules: modules)
        updateManager = UpdateManager(preferences: preferences)
        let usageStore = ApplicationUsageStore(store: repository)
        applicationUsageStore = usageStore
        let usedPreferenceKeys = ["themeMode", "submitWithShiftEnter", "submissionEffect"]
        onboarding = OnboardingState(preferences: preferences,
            applicationUsageIsEmpty: usageStore.usage.isEmpty, usedPreferenceKeys: usedPreferenceKeys,
            hasSavedActionConfiguration: actionConfiguration.hasSavedActionConfiguration)
        recordPanelFollowsCursor = Self.enabledPreference("recordPanelFollowsCursor", in: preferences)
        showsInDock = preferences.object(forKey: "showsInDock") == nil || preferences.bool(forKey: "showsInDock")
        self.aiSources = aiSources
        aiSource = preferences.string(forKey: Self.aiSourceKey) ?? defaultAISourceID
        aiManualConfiguration = preferences.data(forKey: Self.aiManualConfigurationKey)
            .flatMap { try? JSONDecoder().decode(AIProviderPlugin.ManualConfiguration.self, from: $0) } ?? .init()
        super.init()
        refreshAIModel()
    }

    // MARK: - 应用更新

    func markFirstUsePresented() {
        onboarding.markFirstUsePresented()
    }

    func markCopyHintPresented() {
        onboarding.markCopyHintPresented()
    }

    func skipFirstUse() {
        onboarding.skip()
        cancelRecordShortcutTrial()
    }

    /// 仅应用入口调用。测试与 swift run 不会启动网络检查或 Sparkle 窗口。
    func startUpdates() {
        updateManager.start()
    }

    static func updateConfigurationIssue(_ info: [String: Any]) -> String? {
        UpdateManager.configurationIssue(info)
    }

    func checkForUpdates() {
        updateManager.check()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updateManager.setAutomaticChecks(enabled)
    }

    // MARK: - AI 配置

    func setAISource(_ source: String) {
        if source != aiSource {
            preferences.set(aiSourceRevision + 1, forKey: "plugin.ai.sourceRevision")
            invalidateAIConnectionTest()
        }
        aiSource = source
        preferences.set(source, forKey: Self.aiSourceKey)
        refreshAIModel()
    }

    private func refreshAIModel() {
        guard let source = selectedAISource, let key = source.modelPreferenceKey else { aiModel = nil; return }
        let saved = preferences.string(forKey: key)
        aiModel = source.models.first { $0.id == saved }?.id ?? source.models.first?.id
    }

    func setAIModel(_ model: String) {
        guard let source = selectedAISource, let key = source.modelPreferenceKey,
              source.models.contains(where: { $0.id == model }) else { return }
        if model != aiModel {
            preferences.set(aiSourceRevision + 1, forKey: "plugin.ai.sourceRevision")
            invalidateAIConnectionTest()
        }
        aiModel = model
        preferences.set(model, forKey: key)
    }

    func invalidateAIConnectionTest() {
        aiConnectionRevision += 1
        aiConnectionStatus = nil
        actionRegistry.invalidateSharedConfiguration()
    }

    func testAIConnection() async {
        guard !isTestingAIConnection, let test = onTestAIConnection else { return }
        isTestingAIConnection = true
        defer { isTestingAIConnection = false }
        let revision = aiConnectionRevision
        let source = selectedAISource
        let model = source?.models.first { $0.id == aiModel }
        let title = (source?.title ?? aiSource) + (model.map { " · " + $0.title } ?? "")
        aiConnectionStatus = .testing(title)
        do {
            try await test()
            aiConnectionStatus = revision == aiConnectionRevision ? .succeeded(title) : .staleSucceeded
        } catch {
            aiConnectionStatus = revision == aiConnectionRevision
                ? .failed(error.localizedDescription) : .staleFailed
        }
    }

    func saveAIInstructions(_ text: String) throws {
        var next = aiManualConfiguration
        next.instructions = text
        try saveAIManualConfiguration(next)
    }

    func saveAIPrompt(_ text: String, for prompt: AIProviderPlugin.Prompt) throws {
        var next = aiManualConfiguration
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : text
        switch prompt {
        case .supplement: next.supplementPrompt = value
        case .summary: next.summaryPrompt = value
        }
        try saveAIManualConfiguration(next)
    }

    private func saveAIManualConfiguration(_ value: AIProviderPlugin.ManualConfiguration) throws {
        let data = try JSONEncoder().encode(value)
        preferences.set(data, forKey: Self.aiManualConfigurationKey)
        guard preferences.data(forKey: Self.aiManualConfigurationKey) == data else {
            throw AIProviderPlugin.Failure(message: L10n.text("error.settings_save_failed"))
        }
        if value.version != aiManualConfiguration.version { invalidateAIConnectionTest() }
        aiManualConfiguration = value
    }

    func aiRequestConfiguration() throws -> AIProviderPlugin.Configuration {
        guard let source = selectedAISource else {
            throw AIProviderPlugin.Failure(message: L10n.text("error.ai_source_unregistered", aiSource))
        }
        return try source.configure(aiModel)
    }

    /// action 的启用开关（缺省开）。关掉后从 registry 的候选中消失：Jev 候选、
    /// ⌥↕ 目标、capture 选项、本地关键词命中都不再包含它（见 registry 执行快照）。
    func isActionEnabled(_ id: String) -> Bool {
        actionConfiguration.isActionEnabled(id)
    }

    func setActionEnabled(_ enabled: Bool, for id: String) {
        actionConfiguration.setActionEnabled(enabled, for: id)
    }

    /// 用户手动分流规则（短语 → action id），仅本地保存，供设置页读写。
    var intentRules: [IntentRule] { actionConfiguration.intentRules }

    /// 加一条规则：trim 短语，空则忽略；同短语（忽略大小写）覆盖已有，追加在末尾。
    func addIntentRule(phrase: String, actionID: String) {
        actionConfiguration.addIntentRule(phrase: phrase, actionID: actionID)
    }

    /// 删除单条规则。
    func removeIntentRule(id: UUID) {
        actionConfiguration.removeIntentRule(id: id)
    }

    /// 装配会话依赖；AppState 不拥有草稿，也不参与路由状态转换。
    func makeLauncherSession(
        settings: JevSettings = .shared,
        catalog: ApplicationCatalog = ApplicationCatalog(),
        recognize: @escaping IntentRecognition.Recognize = { text, key, capture in
            try await Jev.recognize(text: text, apiKey: key, capture: capture)
        }
    ) -> LauncherSession {
        LauncherSession(repository: repository, registry: actionRegistry, feedback: intentFeedback,
            catalog: catalog, storageAvailable: { [weak self] in self?.storageAvailable ?? false },
            configuration: { .init(revision: settings.revision, hasAPIKey: settings.hasAPIKey) },
            readKey: { try settings.currentAPIKey() }, recognize: recognize,
            applicationUsage: { [weak self] in self?.applicationUsage ?? [:] },
            recordApplicationOpen: { [weak self] in self?.recordApplicationOpen($0) ?? false })
    }

    // MARK: - 应用使用统计

    /// 仅在系统确认打开成功后调用。写入失败仍保留本次会话的排序及待重试增量。
    @discardableResult
    func recordApplicationOpen(_ url: URL, at date: Date = Date()) -> Bool {
        applicationUsageStore.recordOpen(url, at: date)
    }

    @discardableResult
    func saveApplicationUsage() -> Bool {
        applicationUsageStore.save()
    }

    // MARK: - 私有

    private static func enabledPreference(_ key: String, in preferences: UserDefaults) -> Bool {
        preferences.object(forKey: key) == nil || preferences.bool(forKey: key)
    }
}
