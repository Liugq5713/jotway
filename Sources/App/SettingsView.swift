import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

/// 控件与说明合并为一行：说明紧贴控件下方。分组表单里每条说明单独成行会拉高分组、
/// 让竖向节奏发散，收进同一行后与 macOS 系统设置的密度一致。各设置页共用。
@ViewBuilder
func settingRow<Control: View>(_ caption: String?,
    @ViewBuilder control: () -> Control) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        control()
        if let caption {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 设置面板（docs/product/settings.md）：⌘, 唤起。
/// 左侧选择设置分类，右侧显示当前分类的实际配置。
///
/// 热键用库自带的 KeyboardShortcuts.Recorder：改完自动持久化（UserDefaults）
/// 并热更新全局热键，PanelController 的 installHotkey 监听不受影响。
/// 已知限制：macOS 15+ 沙盒下纯 Option 修饰键不能单独录制（默认的 ⌥Space 仍可用）。
struct SettingsView: View {
    enum Page: Hashable {
        case general
        case ai
        case intent
        case actions
        case instructions
        case gettingStarted
        case about

        var title: String {
            switch self {
            case .general: L10n.text("settings.page.general")
            case .ai: "AI"
            case .intent: L10n.text("settings.page.intent")
            case .actions: "Actions"
            case .instructions: "Instructions"
            case .gettingStarted: L10n.text("settings.page.getting_started")
            case .about: L10n.text("settings.page.about")
            }
        }

        var subtitle: String {
            switch self {
            case .general: L10n.text("settings.subtitle.general")
            case .ai: L10n.text("settings.subtitle.ai")
            case .intent: L10n.text("settings.subtitle.intent")
            case .actions: L10n.text("settings.subtitle.actions")
            case .instructions: L10n.text("settings.subtitle.instructions")
            case .gettingStarted: L10n.text("settings.subtitle.getting_started")
            case .about: L10n.text("settings.subtitle.about")
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .ai: "sparkles"
            case .intent: "arrow.triangle.branch"
            case .actions: "bolt.horizontal"
            case .instructions: "text.alignleft"
            case .gettingStarted: "questionmark.circle"
            case .about: "info.circle"
            }
        }
    }

    @MainActor @Observable
    final class Contact {
        static let homepageURL = URL(string: "https://github.com/Liugq5713/jotway")!
        var error: String?
        private let openURL: (URL) -> Bool

        init(openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
            self.openURL = openURL
        }

        func openHomepage() {
            error = nil
            if !openURL(Self.homepageURL) { error = L10n.text("settings.contact.open_failed") }
        }
    }

    @Binding var themeMode: ThemeMode
    let appState: AppState
    private let panelController: PanelController?
    private let checkAIKey: (() throws -> Bool)?
    @State private var contact: Contact
    @State private var selectedPage: Page
    @AppStorage("submissionEffect") private var submissionEffect: SubmissionEffect = .wind
    @State private var selectedActionID: String?
    @State private var shortcutStatus = AppState.recordShortcutStatus()
    @State private var aiKey = ""
    @State private var hasAIKey = false
    @State private var keyStatus = L10n.text("settings.key.not_saved")
    @State private var showsGettingStartedShortcuts = false

    init(themeMode: Binding<ThemeMode>, appState: AppState, initialPage: Page = .general,
         checkAIKey: (() throws -> Bool)? = nil, panelController: PanelController? = nil,
         contact: Contact? = nil) {
        self._themeMode = themeMode
        self.appState = appState
        self.checkAIKey = checkAIKey
        self.panelController = panelController
        self._contact = State(initialValue: contact ?? Contact())
        self._selectedPage = State(initialValue: initialPage)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(.primary.opacity(0.08)).frame(width: 1)
            VStack(spacing: 0) {
                pageHeader
                Divider()
                Group {
                    switch selectedPage {
                    case .general: generalPage
                    case .ai: aiPage
                    case .intent: intentPage
                    case .actions: actionsPage
                    case .instructions: instructionsPage
                    case .gettingStarted: gettingStartedPage
                    case .about: aboutPage
                    }
                }
                .scrollContentBackground(.hidden)
                .frame(maxWidth: 760, maxHeight: .infinity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .toggleStyle(.switch)
        .frame(minWidth: 760, idealWidth: 820, minHeight: 560, idealHeight: 640)
        .onAppear {
            refreshShortcutIssue()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in refreshShortcutIssue() }
        .onReceive(NotificationCenter.default.publisher(for: KeyboardShortcuts.shortcutDidChangeNotification)) { _ in refreshShortcutIssue() }
        .onReceive(NotificationCenter.default.publisher(for: KeyboardShortcuts.registrationStatusDidChangeNotification)) { _ in refreshShortcutIssue() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in refreshShortcutIssue() }
        .onChange(of: appState.generalSettingsRequest) { selectedPage = .general }
        .onChange(of: appState.gettingStartedRequest, initial: true) { _, request in
            if request > 0 { selectedPage = .gettingStarted }
        }
        .onChange(of: selectedPage) { old, new in
            selectedActionID = nil
            if old == .gettingStarted && new != .gettingStarted { panelController?.closeGettingStarted() }
            if new != .about { contact.error = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  !(window is RecordPanel), window.styleMask.contains(.titled) else { return }
            panelController?.closeGettingStarted()
            appState.cancelRecordShortcutTrial()
            contact.error = nil
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                appIcon(size: 32)
                Text("Jotway").font(.headline)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 8)

            List(selection: $selectedPage) {
                Section(L10n.text("settings.sidebar.configuration")) {
                    ForEach([Page.general, .ai, .intent, .actions, .instructions], id: \.self) { page in
                        sidebarLabel(page)
                    }
                }
                Section(L10n.text("settings.sidebar.help")) {
                    ForEach([Page.gettingStarted, .about], id: \.self) { page in
                        sidebarLabel(page)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .accessibilityLabel(L10n.text("settings.sidebar.accessibility"))
        }
        .frame(width: 184)
        .background(.bar)
    }

    private func sidebarLabel(_ page: Page) -> some View {
        Label {
            Text(page.title)
        } icon: {
            Image(systemName: page.symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 20)
        }
        .padding(.vertical, 5)
        .tag(page)
        .accessibilityIdentifier("settings-page-\(page)")
    }

    private var selectedActionEntry: ActionSettingsEntry? {
        selectedActionID.flatMap { appState.actionRegistry.settingsEntry(for: $0) }
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            if let entry = selectedActionEntry, selectedPage == .actions {
                Button { selectedActionID = nil } label: {
                    Image(systemName: "chevron.left")
                }
                .controlSize(.large)
                .help(L10n.text("settings.actions.back"))
                .accessibilityLabel(L10n.text("settings.actions.back"))
                .accessibilityIdentifier("actions-back")
                actionTile(icon: entry.descriptor.systemImageName, tint: entry.descriptor.tint.color)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(selectedPage == .actions ? (selectedActionEntry?.descriptor.localizedSettingsName ?? selectedPage.title) : selectedPage.title)
                    .font(.system(size: 22, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(selectedPage == .actions ? (selectedActionEntry?.descriptor.localizedSummary ?? selectedPage.subtitle) : selectedPage.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private func appIcon(size: CGFloat) -> some View {
        Image(nsImage: NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var instructionsPage: some View {
        if appState.onTestAIConnection != nil {
            Form {
                Section(L10n.text("settings.instructions.background")) {
                    InstructionEditor(title: L10n.text("settings.instructions.background"), saved: appState.aiManualConfiguration.instructions,
                        defaultValue: "", explanation: L10n.text("settings.instructions.background.help"),
                        onSave: appState.saveAIInstructions)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(L10n.text("settings.instructions.unavailable"), systemImage: "text.alignleft",
                description: Text(L10n.text("settings.instructions.unavailable.detail")))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var actionsPage: some View {
        ActionSettingsView(configuration: appState.actionConfiguration,
                           selectedActionID: $selectedActionID)
    }

    private func actionTile(icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
    private var generalPage: some View {
        Form {
            Section(L10n.text("settings.general.appearance")) {
                LabeledContent(L10n.text("settings.general.theme")) {
                    Picker(L10n.text("settings.general.theme"), selection: $themeMode) {
                        Text(L10n.text("settings.general.theme.system")).tag(ThemeMode.system)
                        Text(L10n.text("settings.general.theme.light")).tag(ThemeMode.light)
                        Text(L10n.text("settings.general.theme.dark")).tag(ThemeMode.dark)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
                settingRow(appState.dockPreferenceIssue) {
                    Toggle(L10n.text("settings.general.show_in_dock"), isOn: Binding(
                        get: { appState.showsInDock }, set: { appState.setShowsInDock($0) }))
                }
            }

            Section(L10n.text("settings.general.quick_record")) {
                settingRow(shortcutStatus.issue) {
                    LabeledContent(L10n.text("settings.general.global_shortcut")) {
                        KeyboardShortcuts.Recorder(for: .recordNote)
                            .accessibilityLabel(L10n.text("settings.general.shortcut.accessibility"))
                    }
                }
                if let recommendation = shortcutStatus.recommendation {
                    settingRow(L10n.text("settings.general.shortcut.recommendation_help")) {
                        HStack {
                            Text(L10n.text("settings.general.shortcut.recommended", recommendation.description))
                            Spacer(minLength: 12)
                            Button(L10n.text("settings.general.shortcut.use_recommended")) {
                                let issue = AppState.adoptRecordShortcut(recommendation)
                                refreshShortcutIssue()
                                if let issue { shortcutStatus.issue = issue }
                            }
                        }
                    }
                }
                settingRow(L10n.text("settings.general.follow_cursor.help")) {
                    Toggle(L10n.text("settings.general.follow_cursor"), isOn: Binding(
                        get: { appState.recordPanelFollowsCursor }, set: { appState.recordPanelFollowsCursor = $0 }))
                }
                settingRow(L10n.text("settings.general.submission_effect.help")) {
                    Picker(L10n.text("settings.general.submission_effect"), selection: $submissionEffect) {
                        ForEach(SubmissionEffect.allCases, id: \.self) { effect in
                            Text(effect.title).tag(effect)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section(L10n.text("settings.general.startup")) {
                LaunchAtLoginToggle(title: L10n.text("settings.general.launch_at_login"))
            }
            RuntimeLogSettings()
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var aiPage: some View {
        Form {
            aiSourceSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { refreshAIKeyStatus() }
        .onChange(of: appState.selectedAISource?.id) {
            aiKey = ""
            refreshAIKeyStatus()
        }
        .onDisappear { aiKey = "" }
    }

    private var intentPage: some View {
        Form {
            JevSettingsView(appState: appState)
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var aiSourceSection: some View {
        Section {
            Picker(L10n.text("settings.ai.provider"), selection: Binding(
                get: { appState.aiSource }, set: { appState.setAISource($0) }
            )) {
                ForEach(appState.aiSources) { source in
                    Text(source.title).tag(source.id)
                }
                if appState.selectedAISource == nil {
                    Text(L10n.text("settings.ai.source_unregistered", appState.aiSource)).tag(appState.aiSource)
                }
            }
            .pickerStyle(.menu)
            .disabled(appState.onTestAIConnection == nil)

            if let source = appState.selectedAISource, !source.models.isEmpty {
                Picker(L10n.text("settings.ai.model"), selection: Binding(
                    get: { appState.aiModel ?? "" }, set: { appState.setAIModel($0) }
                )) {
                    ForEach(source.models, id: \.id) { model in
                        Text(model.title).tag(model.id)
                    }
                }
                .disabled(appState.onTestAIConnection == nil)
            }
        } header: {
            Text(L10n.text("settings.ai.source"))
        } footer: {
            Text(appState.onTestAIConnection == nil ? L10n.text("settings.ai.unavailable")
                : appState.selectedAISource.map(localizedSourceDetail) ?? L10n.text("settings.ai.choose_source"))
        }

        if appState.onTestAIConnection != nil {
            if let source = appState.selectedAISource, let keyURL = source.keyURL {
                Section {
                    HStack(spacing: 12) {
                        SecureField(hasAIKey ? L10n.text("settings.key.replace_placeholder") : "\(source.title) API Key", text: Binding(
                            get: { aiKey }, set: { aiKey = $0; appState.invalidateAIConnectionTest() }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .onSubmit { saveAIKey() }
                        .accessibilityLabel("\(source.title) API Key")
                        Button(L10n.text("common.save")) { saveAIKey() }.disabled(aiKey.isEmpty)
                    }
                    HStack(spacing: 12) {
                        Label(keyStatus, systemImage: hasAIKey ? "checkmark.circle" : "key")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if hasAIKey {
                            Button(L10n.text("settings.key.remove"), role: .destructive) { removeAIKey() }
                                .controlSize(.small)
                        }
                    }
                    Link(L10n.text("settings.key.get", source.title), destination: keyURL)
                } header: {
                    Text(L10n.text("settings.key.section"))
                } footer: {
                    Text(L10n.text("settings.key.storage_help"))
                }
            }

            Section {
                HStack(spacing: 12) {
                    Text(L10n.text("settings.connection.verify"))
                    Spacer(minLength: 12)
                    if appState.isTestingAIConnection {
                        ProgressView().controlSize(.small)
                    }
                    Button(appState.isTestingAIConnection ? L10n.text("settings.connection.testing") : L10n.text("settings.connection.test")) {
                        Task { await appState.testAIConnection() }
                    }
                    .disabled(appState.isTestingAIConnection
                        || appState.selectedAISource == nil
                        || (appState.selectedAISource?.keyURL != nil && (!hasAIKey || !aiKey.isEmpty)))
                }
                if let connectionMessage = appState.aiConnectionMessage {
                    Text(connectionMessage).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            } header: {
                Text(L10n.text("settings.connection.section"))
            } footer: {
                Text(L10n.text("settings.ai.connection.help"))
            }
        }
    }

    private func localizedSourceDetail(_ source: AIProviderPlugin.Source) -> String {
        switch source.id {
        case "deepSeek": L10n.text("settings.ai.detail.deepseek")
        case "moonshot": L10n.text("settings.ai.detail.moonshot")
        default: source.detail
        }
    }

    private func refreshAIKeyStatus() {
        guard let hasKey = appState.selectedAISource?.hasKey,
              appState.onTestAIConnection != nil else { return }
        do {
            hasAIKey = try (checkAIKey ?? hasKey)()
            keyStatus = hasAIKey ? L10n.text("settings.key.saved") : L10n.text("settings.key.not_saved")
        } catch {
            hasAIKey = false
            keyStatus = error.localizedDescription
        }
    }

    private func saveAIKey() {
        do {
            guard let save = appState.selectedAISource?.saveKey else { return }
            try save(aiKey)
            aiKey = ""
            hasAIKey = true
            keyStatus = L10n.text("settings.key.saved")
            appState.invalidateAIConnectionTest()
        } catch { keyStatus = error.localizedDescription }
    }

    private func removeAIKey() {
        do {
            guard let remove = appState.selectedAISource?.removeKey else { return }
            try remove()
            aiKey = ""
            hasAIKey = false
            keyStatus = L10n.text("settings.key.removed")
            appState.invalidateAIConnectionTest()
        } catch { keyStatus = error.localizedDescription }
    }

    private func refreshShortcutIssue() {
        shortcutStatus = AppState.recordShortcutStatus()
    }

    private var aboutPage: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    appIcon(size: 64)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Jotway").font(.title2.weight(.semibold))
                        Text(L10n.text("settings.about.tagline"))
                            .foregroundStyle(.secondary)
                        Text(L10n.text("settings.about.version", appState.currentVersion))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            Section(L10n.text("settings.about.updates")) {
                settingRow(L10n.text("settings.about.updates.help")) {
                    Toggle(L10n.text("settings.about.updates.automatic"), isOn: Binding(
                        get: { appState.automaticallyChecksForUpdates },
                        set: { appState.setAutomaticallyChecksForUpdates($0) }
                    ))
                    .disabled(!appState.updatesAvailable)
                }
                HStack {
                    Text(L10n.text("settings.about.updates.check_label"))
                    Spacer(minLength: 12)
                    Button(appState.updateMenuTitle) { appState.checkForUpdates() }
                        .disabled(!appState.canCheckForUpdates)
                }
                if let message = appState.updateMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let url = appState.updateDownloadURL {
                    Link(L10n.text("settings.about.updates.manual"), destination: url)
                }
            }
            Section {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("@Liugq5713").font(.body.weight(.medium)).textSelection(.enabled)
                        Text(L10n.text("settings.about.contact.help"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button(action: contact.openHomepage) {
                        Label("GitHub", systemImage: "arrow.up.right")
                    }
                    .accessibilityLabel(L10n.text("settings.about.contact.github"))
                    .accessibilityIdentifier("contact-open-github")
                }
                .padding(.vertical, 4)
                if let error = contact.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                        .accessibilityIdentifier("contact-open-error")
                }
            } header: {
                Text(L10n.text("settings.about.contact"))
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gettingStartedPage: some View {
        Form {
            Section(L10n.text("guide.quick_start")) {
                Text(L10n.text("guide.quick_start.summary"))
                    .font(.headline)
                gettingStartedStep("1", title: L10n.text("guide.step.open.title"),
                    description: L10n.text("guide.step.open.detail"))
                gettingStartedStep("2", title: L10n.text("guide.step.target.title"),
                    description: L10n.text("guide.step.target.detail"))
                gettingStartedStep("3", title: L10n.text("guide.step.confirm.title"),
                    description: L10n.text("guide.step.confirm.detail"))
                Text(L10n.text("guide.destination.help"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L10n.text("guide.configure_actions")) { selectedPage = .actions }
                    Spacer(minLength: 12)
                    Button(L10n.text("welcome.start")) { panelController?.showRecordFromGettingStarted() }
                        .buttonStyle(.borderedProminent)
                }
            }

            Section(L10n.text("guide.reopen")) {
                LabeledContent(L10n.text("guide.reopen.label"),
                               value: shortcutStatus.shortcut?.description ?? L10n.text("guide.shortcut.not_set"))
                if let issue = shortcutStatus.issue {
                    Text(issue).font(.caption).foregroundStyle(.secondary)
                }
                Text(appState.returnToJotwayHint)
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup(L10n.text("guide.shortcut.change_and_try"), isExpanded: $showsGettingStartedShortcuts) {
                    RecordShortcutOptions(appState: appState).padding(.vertical, 8)
                }
                if let message = appState.shortcutTrialMessage {
                    Text(message).font(.callout).accessibilityAddTraits(.updatesFrequently)
                }
                HStack {
                    Button(L10n.text("guide.show_welcome")) { panelController?.openWelcomeWindow() }
                    Spacer(minLength: 12)
                    if appState.needsFirstUsePresentation {
                        Button(L10n.text("guide.skip")) { appState.skipFirstUse() }.buttonStyle(.link)
                    }
                }
            }

            Section(L10n.text("guide.capabilities")) {
                gettingStartedExample(L10n.text("guide.example.note.title"), input: L10n.text("guide.example.note.input"),
                    result: L10n.text("guide.example.note.result"))
                gettingStartedExample(L10n.text("guide.example.reminder.title"), input: L10n.text("guide.example.reminder.input"),
                    result: L10n.text("guide.example.reminder.result"))
                gettingStartedExample(L10n.text("guide.example.calendar.title"), input: L10n.text("guide.example.calendar.input"),
                    result: L10n.text("guide.example.calendar.result"))
                gettingStartedExample(L10n.text("guide.example.search.title"), input: L10n.text("guide.example.search.input"),
                    result: L10n.text("guide.example.search.result"))
                gettingStartedExample(L10n.text("guide.example.app.title"), input: L10n.text("guide.example.app.input"),
                    result: L10n.text("guide.example.app.result"))
                Text(L10n.text("guide.fallback.help"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L10n.text("guide.time.help"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L10n.text("guide.input_shortcuts")) {
                LabeledContent(L10n.text("guide.shortcut.execute"), value: L10n.text("guide.shortcut.execute.value"))
                LabeledContent(L10n.text("guide.shortcut.newline"), value: "Shift+Enter")
                LabeledContent(L10n.text("guide.shortcut.switch"), value: L10n.text("guide.shortcut.switch.value"))
                LabeledContent(L10n.text("guide.shortcut.hide"), value: "Esc")
                LabeledContent(L10n.text("guide.shortcut.edit"), value: "⌘C / ⌘V / ⌘X / ⌘Z")
                Text(L10n.text("guide.input.help"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L10n.text("guide.composition.help"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L10n.text("guide.intent_ai")) {
                Text(L10n.text("guide.intent.help"))
                Text(L10n.text("guide.intent.local_help"))
                Text(L10n.text("guide.ai.help"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L10n.text("guide.open_intent")) { selectedPage = .intent }
                    Button(L10n.text("guide.open_actions")) { selectedPage = .actions }
                }
            }

            Section(L10n.text("guide.drafts_failures")) {
                Text(L10n.text("guide.drafts.help"))
                Text(L10n.text("guide.failures.help"))
                Text(L10n.text("guide.no_inbox.help"))
            }

            Section {
                DisclosureGroup(L10n.text("guide.privacy")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("guide.privacy.remote"))
                        Text(L10n.text("guide.privacy.local"))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { panelController?.beginGettingStarted() }
        .onDisappear {
            panelController?.closeGettingStarted()
            appState.cancelRecordShortcutTrial()
        }
    }

    private func gettingStartedStep(_ number: String, title: String, description: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(number)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.quaternary, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium))
                Text(description).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 5)
    }

    private func gettingStartedExample(_ title: String, input: String, result: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.body.weight(.medium))
            Text(L10n.text("guide.example.input_format", input)).font(.callout)
            Text(result).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

}

/// 欢迎页与手动入门共用录制及冲突反馈；详细入门提供可取消的试用。
struct RecordShortcutOptions: View {
    var appState: AppState?
    var title: String?
    var subtitle: String?
    @State private var status = AppState.recordShortcutStatus()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title ?? L10n.text("shortcut.change"))
                    if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 12)
                KeyboardShortcuts.Recorder(for: .recordNote)
                    .accessibilityLabel(L10n.text("shortcut.accessibility"))
            }
            if let issue = status.issue { Text(issue).font(.callout).foregroundStyle(.secondary) }
            if let recommendation = status.recommendation {
                Button(L10n.text("shortcut.use_recommended", recommendation.description)) {
                    let issue = AppState.adoptRecordShortcut(recommendation)
                    status = AppState.recordShortcutStatus()
                    if let issue { status.issue = issue }
                }
            }
            if appState?.isTryingRecordShortcut == true {
                Button(L10n.text("shortcut.cancel_trial")) { appState?.cancelRecordShortcutTrial() }
            } else if appState != nil {
                Button(L10n.text("shortcut.try")) {
                    status = AppState.recordShortcutStatus()
                    appState?.beginRecordShortcutTrial(shortcut: status.shortcut, issue: status.issue)
                }
                .disabled(appState == nil || status.shortcut == nil || status.issue != nil)
            }
        }
        .onAppear { status = AppState.recordShortcutStatus() }
        .onReceive(NotificationCenter.default.publisher(for: KeyboardShortcuts.shortcutDidChangeNotification)) { _ in
            status = AppState.recordShortcutStatus()
            appState?.cancelRecordShortcutTrial()
        }
        .onReceive(NotificationCenter.default.publisher(for: KeyboardShortcuts.registrationStatusDidChangeNotification)) { _ in
            status = AppState.recordShortcutStatus()
            if status.issue != nil { appState?.cancelRecordShortcutTrial() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            status = AppState.recordShortcutStatus()
        }
    }
}

/// Only the two plugin prompt headers use this style; collapsed content keeps its local draft and error.
struct PromptHeaderDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        HeaderAndContent(configuration: configuration)
    }

    private struct HeaderAndContent: View {
        let configuration: Configuration
        @FocusState private var headerFocused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    configuration.isExpanded.toggle()
                    headerFocused = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                            .frame(width: 12)
                            .accessibilityHidden(true)
                        configuration.label
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused($headerFocused)
                .accessibilityValue(configuration.isExpanded
                    ? L10n.text("accessibility.expanded") : L10n.text("accessibility.collapsed"))

                // Keep the same subtree instead of removing InstructionEditor's @State on collapse.
                VStack(alignment: .leading, spacing: 8) { configuration.content }
                    .padding(.leading, 16)
                    .padding(.top, configuration.isExpanded ? 8 : 0)
                    .frame(height: configuration.isExpanded ? nil : 0, alignment: .top)
                    .clipped()
                    .opacity(configuration.isExpanded ? 1 : 0)
                    .allowsHitTesting(configuration.isExpanded)
                    .disabled(!configuration.isExpanded)
                    .accessibilityHidden(!configuration.isExpanded)
            }
        }
    }
}

/// The same draft/save/cancel interaction is used by the three actual manual settings.
struct InstructionEditor: View {
    let title: String
    let saved: String
    let defaultValue: String
    let explanation: String
    let onSave: (String) throws -> Void
    @State private var draft: String
    @State private var usesDefault: Bool
    @State private var message: String?

    init(title: String, saved: String, defaultValue: String, explanation: String, onSave: @escaping (String) throws -> Void) {
        self.title = title
        self.saved = saved
        self.defaultValue = defaultValue
        self.explanation = explanation
        self.onSave = onSave
        _draft = State(initialValue: saved.isEmpty ? defaultValue : saved)
        _usesDefault = State(initialValue: saved.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(explanation).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $draft)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 160, idealHeight: 190, maxHeight: 240)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 0.5))
                .accessibilityLabel(title)
                .accessibilityHint(L10n.text("instruction.accessibility_hint"))
            HStack {
                Button(L10n.text("instruction.restore_default")) {
                    draft = defaultValue; usesDefault = true; message = L10n.text("instruction.save_to_apply")
                }
                    .accessibilityIdentifier("reset-\(title)")
                Spacer(minLength: 12)
                Text(L10n.text("instruction.enter_newline")).font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("common.cancel")) { draft = saved.isEmpty ? defaultValue : saved; usesDefault = saved.isEmpty; message = nil }
                    .accessibilityIdentifier("cancel-\(title)")
                Button(L10n.text("common.save")) {
                    do {
                        try onSave(usesDefault ? "" : draft)
                        if !defaultValue.isEmpty && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            draft = defaultValue
                            usesDefault = true
                        }
                        message = L10n.text("instruction.saved")
                    } catch { message = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("save-\(title)")
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary).accessibilityAddTraits(.updatesFrequently) }
        }
        .onChange(of: draft) { _, new in
            if new != defaultValue { usesDefault = false }
        }
        .onChange(of: saved) { old, new in
            if draft == old || (old.isEmpty && draft == defaultValue) || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft = new.isEmpty ? defaultValue : new
                usesDefault = new.isEmpty
            }
        }
        .onChange(of: defaultValue) { old, new in
            if usesDefault && draft == old { draft = new }
        }
    }
}
