import Foundation
import KeyboardShortcuts
import SwiftUI

enum SettingsDestination: Equatable {
    case ai
    case action(String)
}

/// 应用共享状态：启动器输入外壳的草稿、action 注册表、AI 配置、更新、Dock、快捷键。
/// 沉淀层（收件箱记录 / 卡片 / 待办 / 概览 / 完成 / 导出 / 处理面板）已随 LAUNCHER-01 退场。
@MainActor @Observable
final class AppState: NSObject {
    private let repository: LauncherStore
    let browserSource: BrowserSourceSettings
    let clipboard: ClipboardService
    let operationRecorder: OperationRecorder
    private(set) var operationRecordingEnabled: Bool
    private(set) var operationRetentionDays: Int
    @ObservationIgnored private weak var launcherSession: LauncherSession?
    private(set) var instantInsightPrompt: InstantInsightPrompt
    var automaticDraftThinkingPromptsEnabled: Bool {
        didSet {
            preferences.set(automaticDraftThinkingPromptsEnabled, forKey: "automaticDraftThinkingPromptsEnabled")
            launcherSession?.send(.automaticThinkingPreferenceChanged)
        }
    }
    private let preferences: UserDefaults
    var recordPanelFollowsCursor: Bool {
        didSet { preferences.set(recordPanelFollowsCursor, forKey: "recordPanelFollowsCursor") }
    }
    var completionNotificationsEnabled: Bool {
        didSet { preferences.set(completionNotificationsEnabled, forKey: "completionNotificationsEnabled") }
    }
    /// 数据库打开失败时降级内存运行，操作记录明确报告不可持久化。
    let storageAvailable: Bool
    let templateConfiguration: TemplateConfiguration
    let recentSavedDocuments: RecentSavedDocuments
    let actionConfiguration: ActionConfiguration
    /// Periodic review over indexed notes; nil when the notes module isn't available.
    let notesReview: NotesReview?
    let notesModule: AppleNotesModule?
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
    var settingsDestination: SettingsDestination?
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
    let models: ModelConfiguration
    var aiSource: String { models.deepSelection }
    var aiSources: [AIProviderPlugin.Source] {
        get { models.sources }
        set { models.sources = newValue; invalidateAIConnectionTest() }
    }
    var selectedAISource: AIProviderPlugin.Source? { models.deepSource }
    var aiModel: String? { models.deepModel }
    var aiSourceVersion: String {
        models.version(.deep)
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
        SubmissionEffect(rawValue: preferences.string(forKey: "submissionEffect") ?? "") ?? .quick
    }

    var applicationUsage: [String: ApplicationUsage] { applicationUsageStore.usage }
    var hasPendingApplicationUsage: Bool { applicationUsageStore.hasPendingChanges }
    func setOperationRecordingEnabled(_ enabled: Bool) async throws {
        // Stop remains a durable user preference even if deleting existing rows fails.
        operationRecordingEnabled = enabled
        preferences.set(enabled, forKey: "operationRecording.enabled")
        try await operationRecorder.setEnabled(enabled)
    }

    func setOperationRetentionDays(_ days: Int) async throws {
        let days = min(3650, max(1, days))
        operationRetentionDays = days
        preferences.set(days, forKey: "operationRecording.retentionDays")
        try await operationRecorder.setRetention(days: days)
    }

    init(repository: LauncherStore, preferences: UserDefaults = .standard,
         operationStateFileURL: URL? = nil, persistentStorageAvailable: Bool = true,
         aiSources: [AIProviderPlugin.Source] = bundledAISources(),
         modelConfiguration: ModelConfiguration? = nil,
         actionModules: (@MainActor (UserDefaults) -> [any ActionModule])? = nil,
         clipboardService: ClipboardService? = nil) {
        automaticDraftThinkingPromptsEnabled = preferences.bool(forKey: "automaticDraftThinkingPromptsEnabled")
        instantInsightPrompt = InstantInsightPrompt(stored: preferences.object(forKey: InstantInsightPrompt.preferenceKey))
        self.repository = repository
        storageAvailable = persistentStorageAvailable
        let recordingEnabled = preferences.object(forKey: "operationRecording.enabled") == nil
            || preferences.bool(forKey: "operationRecording.enabled")
        operationRecordingEnabled = recordingEnabled
        let savedRetention = preferences.integer(forKey: "operationRecording.retentionDays")
        let retentionDays = savedRetention > 0 ? min(3650, savedRetention) : 90
        operationRetentionDays = retentionDays
        operationRecorder = OperationRecorder(repository: repository, stateFileURL: operationStateFileURL,
            enabled: recordingEnabled, retentionDays: retentionDays,
            storageAvailable: persistentStorageAvailable)
        self.preferences = preferences
        let browserSource = clipboardService?.sourceSettings ?? BrowserSourceSettings(preferences: preferences)
        self.browserSource = browserSource
        clipboard = clipboardService ?? ClipboardService(sourceSettings: browserSource, preferences: preferences)
        let models = modelConfiguration ?? ModelConfiguration(preferences: preferences, sources: aiSources)
        self.models = models
        let modules = actionModules?(preferences) ?? BundledActions.modules(preferences: preferences, models: models, clipboard: clipboard.history)
        notesModule = modules.compactMap { $0 as? AppleNotesModule }.first
        notesReview = notesModule.map { NotesReview(preferences: preferences, library: $0.reviewLibrary) }
        templateConfiguration = TemplateConfiguration(defaults: preferences)
        recentSavedDocuments = RecentSavedDocuments(defaults: preferences)
        actionConfiguration = ActionConfiguration(preferences: preferences, modules: modules)
        updateManager = UpdateManager(preferences: preferences)
        let usageStore = ApplicationUsageStore(store: repository)
        applicationUsageStore = usageStore
        let usedPreferenceKeys = ["themeMode", "submitWithShiftEnter", "submissionEffect"]
        onboarding = OnboardingState(preferences: preferences,
            applicationUsageIsEmpty: usageStore.usage.isEmpty, usedPreferenceKeys: usedPreferenceKeys,
            hasSavedActionConfiguration: actionConfiguration.hasSavedActionConfiguration)
        recordPanelFollowsCursor = Self.enabledPreference("recordPanelFollowsCursor", in: preferences)
        completionNotificationsEnabled = preferences.bool(forKey: "completionNotificationsEnabled")
        showsInDock = preferences.object(forKey: "showsInDock") == nil || preferences.bool(forKey: "showsInDock")
        aiManualConfiguration = preferences.data(forKey: Self.aiManualConfigurationKey)
            .flatMap { try? JSONDecoder().decode(AIProviderPlugin.ManualConfiguration.self, from: $0) } ?? .init()
        super.init()
        observeModelConfiguration()

    }

    private func observeModelConfiguration() {
        withObservationTracking { _ = models.version(.deep); _ = models.version(.fast) } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.launcherSession?.send(.thinkingPreferencesChanged)
                self?.invalidateAIConnectionTest()
                self?.observeModelConfiguration()
            }
        }
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

    func saveInstantInsightPrompt(_ text: String) throws {
        guard text.utf8.count <= InstantInsightPrompt.maximumBytes else {
            throw AIProviderPlugin.Failure(message: L10n.text("thinking.prompt.too_large"))
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : text
        let key = InstantInsightPrompt.preferenceKey
        let previous = preferences.object(forKey: key)
        preferences.set(value, forKey: key)
        guard preferences.object(forKey: key) as? String == value else {
            if let previous { preferences.set(previous, forKey: key) }
            else { preferences.removeObject(forKey: key) }
            throw AIProviderPlugin.Failure(message: L10n.text("error.settings_save_failed"))
        }
        let next = InstantInsightPrompt(stored: value)
        let changed = next.snapshot != instantInsightPrompt.snapshot
        instantInsightPrompt = next
        if changed { launcherSession?.send(.thinkingPreferencesChanged) }
    }

    func saveAIPrompt(_ text: String, for prompt: AIProviderPlugin.Prompt) throws {
        var next = aiManualConfiguration
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : text
        switch prompt {
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
        try models.textConfiguration(.deep)
    }

    func isActionEnabled(_ id: String) -> Bool {
        actionConfiguration.isActionEnabled(id)
    }

    func setActionEnabled(_ enabled: Bool, for id: String) {
        actionConfiguration.setActionEnabled(enabled, for: id)
    }

    /// 装配会话依赖；AppState 不拥有草稿，也不参与路由状态转换。
    func makeLauncherSession(
        catalog: ApplicationCatalog = ApplicationCatalog()
    ) -> LauncherSession {
        let session = LauncherSession(registry: actionRegistry, recorder: operationRecorder,
            catalog: catalog, clipboard: clipboard, review: notesReview,
            thinkingPromptFactory: { [models] in
                let version = models.version(.fast)
                return try models.text(.fast, validate: {
                    guard await models.version(.fast) == version else { throw CancellationError() }
                })
            },
            thinkingFastVersion: { [models] in models.version(.fast) },
            thinkingInstructions: { [weak self] in self?.instantInsightPrompt.snapshot },
            aiCapabilityReady: { [models] in models.isTextReady($0) },
            automaticThinkingEnabled: { [weak self] in self?.automaticDraftThinkingPromptsEnabled ?? false },
            applicationUsage: { [weak self] in self?.applicationUsage ?? [:] },
            recordApplicationOpen: { [weak self] in self?.recordApplicationOpen($0) ?? false },
            templates: { [templateConfiguration] in templateConfiguration.templates },
            recentSavedDocuments: recentSavedDocuments)
        launcherSession = session
        return session
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
