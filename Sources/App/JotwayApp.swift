import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let recordNote = Self("recordNote", default: .init(.space, modifiers: [.command, .shift]))
}

enum ThemeMode: String {
    case system, light, dark

    @MainActor
    func apply() {
        // nil 交还系统管理；面板、SwiftUI 内容和原生编辑器一起继承应用外观。
        switch self {
        case .system:
            NSApplication.shared.appearance = nil
        case .light:
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

@main
struct JotwayApp: App {
    @NSApplicationDelegateAdaptor(JotwayAppDelegate.self) private var appDelegate
    @AppStorage("themeMode") private var themeMode: ThemeMode = .system
    @State private var appState: AppState
    @State private var panelController: PanelController

    init() {
        let repository: LauncherStore
        var persistentStorageAvailable = true
        do {
            repository = try JotwayAppDelegate.measureStartup("storage") { try LauncherStore.makeDefault() }
        } catch {
            fputs("[Jotway] Database initialization failed; using in-memory storage: \(error)\n", stderr)
            repository = LauncherStore.inMemory()
            persistentStorageAvailable = false
        }

        let appState = JotwayAppDelegate.measureStartup("state") { AppState(repository: repository) }
        appState.storageAvailable = persistentStorageAvailable
        JotwayAppDelegate.measureStartup("submission_hooks") {
            installPlugins(into: appState)
        }
        _appState = State(initialValue: appState)

        // SwiftUI 在主线程序列化创建 App，此处可安全假设 MainActor
        let panelController = MainActor.assumeIsolated {
            let controller = JotwayAppDelegate.measureStartup("input_entry") {
                // 主路由：启动即读取密钥状态，配置过 Jev 的用户无需先打开设置即可识别。
                JevSettings.shared.refreshKeyStatus()
                let controller = PanelController(appState: appState, session: appState.makeLauncherSession())
                controller.installHotkey()
                return controller
            }
            appState.prepareForUpdate = { [weak controller] in
                guard let controller else { return L10n.text("error.cannot_confirm_editor_saved") }
                return controller.prepareForUpdate()
            }
            return controller
        }
        _panelController = State(initialValue: panelController)
        appDelegate.panelController = panelController
        appDelegate.appState = appState

        // 在任何窗口创建之前恢复偏好；无法识别的值由 AppStorage 回退为 system。
        MainActor.assumeIsolated { themeMode.apply() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(appState: appState, panelController: panelController)
        } label: {
            MenuBarLabel()
        }

        // 设置场景（docs/product/settings.md）：获得「设置… ⌘,」原生行为
        Settings {
            SettingsView(themeMode: $themeMode, appState: appState, panelController: panelController)
        }
        .defaultSize(width: 820, height: 640)
        .windowResizability(.contentMinSize)
        .onChange(of: themeMode) {
            themeMode.apply()
        }
    }
}

/// AppKit 的启动事件保留登录项来源；SwiftUI 的视图出现不代表用户主动启动。
@MainActor
final class JotwayAppDelegate: NSObject, NSApplicationDelegate {
    weak var panelController: PanelController?
    weak var appState: AppState?
    private var quitting = false
    private(set) var deferredStartupTask: Task<Void, Never>?

    /// 可选分段计时只记录阶段名和耗时，不记录正文。默认不输出。
    static func measureStartup<T>(_ stage: String, _ work: () throws -> T) rethrows -> T {
        let start = ProcessInfo.processInfo.systemUptime
        defer {
            if ProcessInfo.processInfo.environment["JOTWAY_STARTUP_TIMING"] == "1" {
                let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
                fputs(String(format: "[Jotway.Startup] %@ %.3f ms\n", stage, milliseconds), stderr)
            }
        }
        return try work()
    }

    /// 提交所需的存储和 Hook 已同步安装；每项自动工作开始前让出主线程。
    func startDeferredWork(afterStep: (@MainActor (String) -> Void)? = nil) {
        guard deferredStartupTask == nil, !quitting else { return }
        deferredStartupTask = Task(priority: .utility) { [weak self] in
            guard let self, let app = self.appState else { return }
            await Task.yield()
            guard !Task.isCancelled, !self.quitting else { return }
            Self.measureStartup("panel_prewarm") { _ = self.panelController?.prewarmRecordPanel() }
            afterStep?("panel_prewarm")

            await Task.yield()
            guard !Task.isCancelled, !self.quitting else { return }
            Self.measureStartup("application_preload") { self.panelController?.preloadApplications() }
            afterStep?("application_preload")

            await Task.yield()
            guard !Task.isCancelled, !self.quitting else { return }
            Self.measureStartup("updates") { app.startUpdates() }
            afterStep?("updates")
        }
    }

    func cancelDeferredWork() {
        deferredStartupTask?.cancel()
        panelController?.cancelApplicationPreload()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting { return .terminateNow }
        if let reason = panelController?.prepareForUpdate() {
            fputs("[Jotway] Could not save before quitting: \(reason)\n", stderr)
            return .terminateCancel
        }
        quitting = true
        cancelDeferredWork()
        return .terminateNow
    }

    static func isInteractiveLaunch(_ event: NSAppleEventDescriptor?, isActive: Bool, arguments: [String]) -> Bool {
        guard !arguments.contains("--jotway-update-relaunch"), let event,
              event.eventClass == kCoreEventClass,
              event.eventID == kAEOpenApplication || event.eventID == kAEReopenApplication else { return false }
        let source = event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        guard source != keyAELaunchedAsLogInItem, source != keyAELaunchedAsServiceItem else { return false }
        // 显式后台打开不弹窗；reopen 本身就是返回入口，可能先于应用激活到达。
        return event.paramDescriptor(forKeyword: kAEApplicationActivationExpected)?.booleanValue
            ?? (event.eventID == kAEReopenApplication || isActive)
    }

    static func isInteractiveReopen(_ event: NSAppleEventDescriptor?) -> Bool {
        // AppKit 已通过 delegate 回调确认这是 reopen；没有事件详情时也应响应。
        // 更新重启参数只抑制启动，不能屏蔽同一进程中后续的 Dock 点击。
        guard let event else { return true }
        return isInteractiveLaunch(event, isActive: false, arguments: [])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        RuntimeLog.Context(module: .app).emit(.startup)
        // currentAppleEvent 在系统结束事件处理后失效；异步读取前必须复制，不能只持有原对象。
        let event = NSAppleEventManager.shared().currentAppleEvent?.copy() as? NSAppleEventDescriptor
        let interactive = Self.isInteractiveLaunch(event, isActive: NSApp.isActive, arguments: CommandLine.arguments)
        appState?.applyDockPreference()
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.quitting else { return }
            if interactive {
                self.panelController?.showWorkWindow(atLaunch: true)
            }
            self.startDeferredWork()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.intentFeedback.flushBeforeExit()
        RuntimeLog.Context(module: .app).emit(.shutdown)
        RuntimeLog.shared.flush()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Self.isInteractiveReopen(NSAppleEventManager.shared().currentAppleEvent) {
            panelController?.showWorkWindow()
        }
        return false
    }
}
