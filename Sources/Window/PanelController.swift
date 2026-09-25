import AppKit
import KeyboardShortcuts
import SwiftUI

/// 快速记录面板、系统事件与原生焦点适配；业务会话由 LauncherSession 持有。
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private let pasteboard: NSPasteboard
    private let openApplication: @MainActor (URL, NSWorkspace.OpenConfiguration, @escaping @MainActor (Result<NSRunningApplication, Error>) -> Void) -> Void
    private let presentActionSetup: @MainActor (NSWindow) -> Void
    private var recordPanel: RecordPanel?
    private(set) var welcomeWindow: NSPanel?
    private(set) var actionSetupWindow: NSWindow?
    private var actionSetupRequest: ActionSetupRequest?
    private var restoresVisibleEditorAfterActionSetup = false
    private var returnsToWorkAfterWelcome = false
    let session: LauncherSession
    private let editorFocusTarget: EditorFocusTarget
    private var hotkeyInstalled = false
    private var workspaceObserver: NSObjectProtocol?
    private var intentObservers: [NSObjectProtocol] = []
    private var pendingGettingStarted: (() -> Void)?
    private var preservesEditorAfterGettingStarted = false
    /// 普通淡出或提交退场进行中；提交退场的真实窗口已隐藏，重新唤起走正常草稿恢复。
    private var isHidingPanel = false

    init(
        appState: AppState,
        session: LauncherSession,
        pasteboard: NSPasteboard = .general,
        openApplication: @escaping @MainActor (URL, NSWorkspace.OpenConfiguration, @escaping @MainActor (Result<NSRunningApplication, Error>) -> Void) -> Void
            = PanelController.openSystemApplication,
        presentActionSetup: @escaping @MainActor (NSWindow) -> Void = {
            NSApp.activate(ignoringOtherApps: true)
            $0.makeKeyAndOrderFront(nil)
        }
    ) {
        self.appState = appState
        self.session = session
        self.editorFocusTarget = EditorFocusTarget()
        self.pasteboard = pasteboard
        self.openApplication = openApplication
        self.presentActionSetup = presentActionSetup
        lastObservedPasteboardChangeCount = pasteboard.changeCount
        super.init()
        session.handleEffect = { [weak self] effect in self?.handleSessionEffect(effect) ?? false }
        for name in [JevSettings.didChangeNotification, ActionRegistry.didChangeNotification] {
            intentObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak session] _ in
                MainActor.assumeIsolated { session?.send(.refreshConfiguration) }
            })
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak appState] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { appState?.shortcutTrialLeftJotway() }
        }
        startPasteboardMonitor()
    }

    private func synchronizeEditorInput() {
        guard let editor = editorFocusTarget.textView as? EditorTextView else { return }
        // false 由原生组词结束事件提供，不能在确认路径提前清掉尚未结束的组词状态。
        if editor.hasMarkedText() { session.send(.compositionChanged(true)) }
        session.send(.inputChanged(editor.string))
    }

    private func sendLauncherEvent(_ event: LauncherEvent) {
        switch event {
        case .inputChanged:
            appState.cancelRecordShortcutTrial()
        case .confirm, .preserveDraft:
            synchronizeEditorInput()
        case .cancel:
            guard !isHidingPanel else { return }
            synchronizeEditorInput()
        case .panelPresented:
            guard !isHidingPanel else { return }
        case .panelDismissed:
            closeGettingStarted()
            preservesEditorAfterGettingStarted = false
            returnsToWorkAfterWelcome = false
        case .externalFocusChanged:
            if !NSApp.isActive { appState.shortcutTrialLeftJotway() }
        default:
            break
        }
        session.send(event)
        if case .compositionChanged(false) = event {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.editorFocusTarget.textView?.hasMarkedText() != true else { return }
                self.synchronizeEditorInput()
                let open = self.pendingGettingStarted
                self.pendingGettingStarted = nil
                open?()
                self.session.send(.refreshConfiguration)
            }
        }
    }

    @discardableResult
    private func handleSessionEffect(_ effect: LauncherEffect) -> Bool {
        switch effect {
        case .replaceEditor(let content, let reason):
            guard let editor = editorFocusTarget.textView as? EditorTextView else { return true }
            return editor.setPlainText(content, reason: reason == .newDraft ? .newDraft : .restoreDraft)
        case .prepareSubmission: recordPanel?.prepareSubmissionAnimation()
        case .cancelSubmission: recordPanel?.cancelSubmissionAnimation()
        case .hidePanel(let submitted, let policy):
            hideRecordPanel(submitted: submitted, keepingExternalFocus: policy == .keepDestinationFrontmost)
        case .hideForApplicationLaunch:
            pendingGettingStarted = nil
            isHidingPanel = true
            recordPanel?.hideForApplicationLaunch()
            isHidingPanel = false
        case .showPanel: showRecordPanel()
        case .showActionSetup(let request): showActionSetup(request)
        case .closeActionSetup(let id): closeActionSetup(id)
        case .restoreEditorAfterSetup: restoreEditorAfterActionSetup()
        case .openApplication(let url, let completion):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false
            configuration.allowsRunningApplicationSubstitution = false
            configuration.promptsUserIfNeeded = false
            openApplication(url, configuration) { completion($0.map { _ in () }) }
        }
        return true
    }

    isolated deinit {
        actionSetupRequest?.snapshot.setup.invalidate()
        actionSetupWindow?.delegate = nil
        (actionSetupWindow?.contentView as? ActionSetupHostingView)?.onPreferredSizeChange = nil
        if let host = actionSetupWindow?.contentView as? NSHostingView<AnyView> {
            host.rootView = AnyView(EmptyView())
        }
        actionSetupWindow?.contentView = nil
        actionSetupWindow?.close()
        pasteboardMonitor?.invalidate()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        for observer in intentObservers { NotificationCenter.default.removeObserver(observer) }
    }

    func installHotkey() {
        guard !hotkeyInstalled else { return }
        hotkeyInstalled = true
        KeyboardShortcuts.onKeyDown(for: .recordNote) { [weak self] in
            Task { @MainActor in
                self?.handleRecordHotkey()
            }
        }
    }

    // MARK: - 记录模式（全局热键唤起，非激活闪现）

    /// 只有全局回调能完成试用；Dock、菜单和录制器不经过这条路径。
    private func handleRecordHotkey() {
        let shortcut = KeyboardShortcuts.getShortcut(for: .recordNote)
        let external = !NSApp.isActive && recordPanel?.isKeyWindow != true
        if appState.canCompleteShortcutTrial(shortcut: shortcut, fromExternalApplication: external) {
            showRecordPanel()
            appState.completeRecordShortcutTrial(shortcut: shortcut, fromExternalApplication: external,
                presented: recordPanel?.isVisible == true && recordPanel?.isKeyWindow == true)
        } else {
            toggleRecordPanel()
        }
    }

    /// Sparkle 在最终安装之前调用。返回原因时取消本次安装，不延迟自动重启。
    func prepareForUpdate() -> String? {
        guard !isHidingPanel else { return L10n.text("update.blocked.panel_closing") }
        guard actionSetupRequest == nil, !session.state.isConfiguringAction else {
            return L10n.text("update.blocked.action_setup")
        }
        guard !session.state.isOpeningApplication else { return L10n.text("update.blocked.app_opening") }
        guard editorFocusTarget.textView?.hasMarkedText() != true else {
            return L10n.text("update.blocked.composition")
        }
        guard appState.saveApplicationUsage() else { return L10n.text("update.blocked.usage_save") }
        // 从未准备编辑器时，没有需要提交的会话草稿。
        guard session.state.hasPreparedDraft else { return nil }
        guard preserveDraft() else { return L10n.text("update.blocked.draft_save") }
        return nil
    }

    func toggleRecordPanel() {
        if focusActionSetupIfNeeded() { return }
        if welcomeWindow?.isVisible == true {
            startRecordingFromWelcome()
            return
        }
        if isHidingPanel, let panel = recordPanel, panel.isVisible {
            // 淡出动画中再次唤起：直接淡回，草稿状态原样保留
            isHidingPanel = false
            session.send(.panelPresented)
            panel.animateIn()
            return
        }
        if recordPanel?.isVisible == true {
            // 热键关闭 = 关闭面板：先暂存草稿再隐藏
            guard preserveDraft() else { return }
            hideRecordPanel()
        } else {
            showRecordPanel()
        }
    }

    func showRecordPanel() {
        if focusActionSetupIfNeeded() { return }
        if welcomeWindow?.isVisible == true {
            startRecordingFromWelcome()
            return
        }
        if preservesEditorAfterGettingStarted, session.state.hasPreparedDraft {
            showRecordFromGettingStarted()
            return
        }
        guard let panel = prepareRecordPanel() else { return }
        closeGettingStarted(cancelShortcutTrial: false)
        panel.showPanel()
    }

    /// 主动打开不使用热键的 toggle，也不以首次提示标记决定是否显示工作窗口。
    func showWorkWindow(atLaunch: Bool = false) {
        if focusActionSetupIfNeeded() { return }
        // 在恢复草稿/追加新剪贴板引用之前判断，刚准备的新编辑区仍需正常显示并聚焦。
        let preservesEditor = recordPanel?.isVisible == true || shouldPreserveRecordEditor || preservesEditorAfterGettingStarted
        guard let window = prepareWorkWindow(atLaunch: atLaunch) else { return }
        if let panel = window as? RecordPanel {
            closeGettingStarted(cancelShortcutTrial: false)
            if preservesEditor {
                if isHidingPanel {
                    isHidingPanel = false
                    session.send(.panelPresented)
                    panel.animateIn() // 让旧淡出回调失效，不执行它原本的窗口切换。
                }
                // 不再填回草稿、不粘贴剪贴板、不移动光标，也不改变组词和撤销现场。
                panel.orderFrontRegardless()
                panel.makeKey()
                preservesEditorAfterGettingStarted = false
            } else {
                panel.showPanel()
            }
        } else if window === welcomeWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// 选择已有工作窗口或准备草稿；不显示窗口，允许离屏检查同一条选择路径。
    /// visibleWindows 按前后顺序传入；默认读取 AppKit 的实际可见窗口。
    func prepareWorkWindow(atLaunch: Bool = false, visibleWindows: [NSWindow]? = nil) -> NSWindow? {
        if let actionSetupWindow, actionSetupRequest != nil { return actionSetupWindow }
        guard !atLaunch || !appState.skipsFirstUseAtLaunch else { return nil }
        if let welcomeWindow, welcomeWindow.isVisible { return welcomeWindow }
        if shouldPreserveRecordEditor, let panel = recordPanel { return panel }
        let windows = visibleWindows ?? NSApp.orderedWindows.filter(\.isVisible)
        // 设置使用 SwiftUI 创建的普通标题窗口，不依赖其私有窗口标识。
        // 排除菜单、提示气泡和提交动画等不能接收键盘的辅助窗口。
        if let window = windows.first(where: {
            $0 === recordPanel || ($0.canBecomeKey && $0.styleMask.contains(.titled))
        }) {
            return window
        }
        // 欢迎先于真实草稿恢复和剪贴板导入；已开始的编辑会话优先。
        if appState.needsFirstUsePresentation, !session.state.hasPreparedDraft {
            return prepareWelcomeWindow(automatic: true)
        }
        return prepareRecordPanel()
    }

    /// 只构造欢迎视图；实际可见回调才消费自动展示机会。
    func prepareWelcomeWindow(automatic: Bool = false) -> NSPanel? {
        guard editorFocusTarget.textView?.hasMarkedText() != true else { return nil }
        if let welcomeWindow, welcomeWindow.isVisible { return welcomeWindow }
        if !automatic { beginGettingStarted() }
        if welcomeWindow == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = L10n.text("welcome.title")
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.contentMinSize = NSSize(width: 480, height: 440)
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.delegate = self
            window.center()
            welcomeWindow = window
        }
        let host = NSHostingView(rootView: WelcomeView(
            onGetStarted: { [weak self] in self?.startRecordingFromWelcome() },
            onPresented: { [weak appState] in
                if automatic { appState?.markFirstUsePresented() }
            }))
        host.sizingOptions = []
        welcomeWindow?.contentView = host
        return welcomeWindow
    }

    func openWelcomeWindow(present: @escaping (NSWindow) -> Void = { $0.makeKeyAndOrderFront(nil) }) {
        guard let window = prepareWelcomeWindow() else {
            pendingGettingStarted = { [weak self] in self?.openWelcomeWindow(present: present) }
            return
        }
        pendingGettingStarted = nil
        present(window)
    }

    /// Get Started 与欢迎期间的全局热键共用明确的 show 路径。
    func prepareRecordFromWelcome() -> RecordPanel? {
        guard editorFocusTarget.textView?.hasMarkedText() != true else { return nil }
        welcomeWindow?.close()
        closeGettingStarted()
        returnsToWorkAfterWelcome = true
        return prepareRecordPanel()
    }

    private func startRecordingFromWelcome() {
        guard let panel = prepareRecordFromWelcome() else { return }
        if preservesEditorAfterGettingStarted {
            showRecordFromGettingStarted()
        } else {
            panel.showPanel()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === actionSetupWindow, let request = actionSetupRequest {
            finishActionSetup(request.id, result: .cancelled, windowIsClosing: true)
        } else if window === welcomeWindow {
            closeGettingStarted()
        }
    }

    // MARK: - 模块配置窗口

    /// 配置入口只由确认 effect 打开；重新唤起复用原窗口，不创建新草稿或再次授权。
    private func showActionSetup(_ request: ActionSetupRequest) {
        guard session.state.isConfiguringAction else {
            request.snapshot.setup.invalidate()
            return
        }
        if actionSetupRequest?.id == request.id {
            _ = focusActionSetupIfNeeded()
            return
        }
        if let previous = actionSetupRequest {
            closeActionSetup(previous.id)
        } else {
            restoresVisibleEditorAfterActionSetup = recordPanel?.isVisible == true
        }
        pendingGettingStarted = nil
        appState.cancelRecordShortcutTrial()
        actionSetupRequest = request
        recordPanel?.hideForGettingStarted()
        isHidingPanel = false

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = request.snapshot.setup.title
        window.isReleasedWhenClosed = false
        window.delegate = self
        actionSetupWindow = window
        let view = request.snapshot.setup.makeView { [weak self] result in
            self?.finishActionSetup(request.id, result: result)
        }
        // makeView 的同步完成回调也遵守令牌校验，不能重新挂回已关闭的视图。
        guard actionSetupRequest?.id == request.id, actionSetupWindow === window else { return }
        let host = ActionSetupHostingView(rootView: view)
        host.onPreferredSizeChange = { [weak self, weak window] size in
            guard let self, let window else { return }
            self.fitActionSetupWindow(window, to: size, requestID: request.id)
        }
        window.contentView = host
        fitActionSetupWindow(window, to: host.fittingSize, requestID: request.id)
        guard actionSetupRequest?.id == request.id, actionSetupWindow === window else { return }
        window.center()
        presentActionSetup(window)
    }

    /// 配置视图的异步状态可改变高度；保持顶边，不让旧窗口的布局回调影响新会话。
    private func fitActionSetupWindow(_ window: NSWindow, to preferredSize: NSSize, requestID: UUID) {
        guard actionSetupRequest?.id == requestID, actionSetupWindow === window,
              preferredSize.width.isFinite, preferredSize.height.isFinite else { return }
        let contentSize = NSSize(width: max(ceil(preferredSize.width), 360),
                                 height: max(ceil(preferredSize.height), 240))
        let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        guard abs(window.frame.width - frameSize.width) > 0.5
                || abs(window.frame.height - frameSize.height) > 0.5 else { return }
        let frame = NSRect(x: window.frame.minX, y: window.frame.maxY - frameSize.height,
                           width: frameSize.width, height: frameSize.height)
        window.setFrame(frame, display: window.isVisible)
    }

    @discardableResult
    private func focusActionSetupIfNeeded() -> Bool {
        guard actionSetupRequest != nil, let window = actionSetupWindow else { return false }
        presentActionSetup(window)
        return true
    }

    private func finishActionSetup(_ id: UUID, result: ActionSetupResult, windowIsClosing: Bool = false) {
        guard actionSetupRequest?.id == id else { return }
        closeActionSetup(id, windowIsClosing: windowIsClosing)
        session.send(.actionSetupFinished(id, result))
    }

    /// 先使模块任务失效，再拆除 hosting；不依赖 NSWindow.close 是否触发 onDisappear。
    private func closeActionSetup(_ id: UUID, windowIsClosing: Bool = false) {
        guard let request = actionSetupRequest, request.id == id else { return }
        let window = actionSetupWindow
        actionSetupRequest = nil
        actionSetupWindow = nil
        // 关闭不决定是否恢复焦点；仅会话校验通过后发出的 restore effect 可以恢复。
        request.snapshot.setup.invalidate()
        window?.delegate = nil
        (window?.contentView as? ActionSetupHostingView)?.onPreferredSizeChange = nil
        if let host = window?.contentView as? NSHostingView<AnyView> {
            host.rootView = AnyView(EmptyView())
        }
        window?.contentView = nil
        if !windowIsClosing { window?.close() }
    }

    private func restoreEditorAfterActionSetup() {
        let shouldShow = restoresVisibleEditorAfterActionSetup
        restoresVisibleEditorAfterActionSetup = false
        guard shouldShow, actionSetupRequest == nil, !session.state.isConfiguringAction,
              session.state.hasPreparedDraft, let panel = recordPanel else { return }
        panel.cancelSubmissionAnimation()
        isHidingPanel = false
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(editorFocusTarget.textView)
        preservesEditorAfterGettingStarted = false
    }

    private var shouldPreserveRecordEditor: Bool {
        guard session.state.hasPreparedDraft else { return false }
        if editorFocusTarget.textView?.hasMarkedText() == true { return true }
        // 暂存失败时内存正文仍是最新内容，不能被旧草稿覆盖。
        return !isHidingPanel && session.state.hasUnsavedChanges
    }

    /// 先准备并接受编辑内容，再由 showRecordPanel 显示窗口。
    /// 创建/恢复编辑区不要求将窗口置前，供已有面板复用同一条路径。
    func prepareRecordPanel() -> RecordPanel? {
        guard !focusActionSetupIfNeeded() else { return nil }
        guard editorFocusTarget.textView?.hasMarkedText() != true else { return nil }
        editorFocusTarget.preserveSelectionOnNextFocus = false
        if preservesEditorAfterGettingStarted, session.state.hasPreparedDraft, let panel = recordPanel { return panel }
        if let panel = recordPanel, panel.isVisible, !isHidingPanel {
            // 暂存失败时，重新唤起不能用旧草稿覆盖内存内容。
            return panel
        }
        session.send(.panelPrepared(quote: consumeRecentPasteboardQuote()))
        guard session.state.lastEventSucceeded else { return nil }
        recordPanel?.cancelSubmissionAnimation()
        isHidingPanel = false
        return makeRecordPanel()
    }

    /// 只预建隐藏视图；不得恢复、消费或写回真实草稿。
    @discardableResult
    func prewarmRecordPanel() -> RecordPanel? {
        guard recordPanel == nil else { return nil }
        let panel = makeRecordPanel()
        panel.contentView?.layoutSubtreeIfNeeded()
        return panel
    }

    func preloadApplications() {
        session.send(.preloadApplications)
    }

    func cancelApplicationPreload() {
        session.send(.cancelApplicationPreload)
    }

    private func makeRecordPanel() -> RecordPanel {
        if recordPanel == nil {
            recordPanel = RecordPanel(
                appState: appState,
                text: Binding(
                    get: { [weak session] in session?.state.draftContent ?? "" },
                    set: { [weak self] in self?.sendLauncherEvent(.inputChanged($0)) }
                ),
                focusTarget: editorFocusTarget,
                state: session.state,
                send: { [weak self] in self?.sendLauncherEvent($0) }
            )
        }
        recordPanel?.title = L10n.text("settings.general.quick_record")
        return recordPanel!
    }

    private static func openSystemApplication(
        _ url: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completion: @escaping @MainActor (Result<NSRunningApplication, Error>) -> Void
    ) {
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
            Task { @MainActor in
                if let application, error == nil {
                    completion(.success(application))
                } else {
                    completion(.failure(error ?? NSError(
                        domain: NSCocoaErrorDomain, code: NSFileReadUnknownError,
                        userInfo: [NSLocalizedDescriptionKey: L10n.text("launcher.system_open_failed")]
                    )))
                }
            }
        }
    }

    private var lastObservedPasteboardChangeCount: Int
    private var lastPasteboardCheckAt = Date()
    private var pasteboardChangedAt: Date?

    /// 后台只记录变化次数和发现时间；唤起面板之前不读取剪贴板文字。
    func observePasteboardChange(at date: Date = Date()) {
        defer { lastPasteboardCheckAt = date }
        let changeCount = pasteboard.changeCount
        guard changeCount != lastObservedPasteboardChangeCount else { return }
        lastObservedPasteboardChangeCount = changeCount
        // 用上次检查作为保守起点，发现延迟不能延长引用时限；长停顿或时间倒退时跳过。
        pasteboardChangedAt = (0...1).contains(date.timeIntervalSince(lastPasteboardCheckAt)) ? lastPasteboardCheckAt : nil
    }

    /// 每次复制最多引用一次。打开时补查一次，覆盖复制后尚未到下个轮询 tick 的情况。
    func consumeRecentPasteboardQuote(at date: Date = Date()) -> String? {
        observePasteboardChange(at: date)
        defer { pasteboardChangedAt = nil }
        guard !session.state.isOpeningApplication,
              let changedAt = pasteboardChangedAt,
              (0...1).contains(date.timeIntervalSince(changedAt)) else { return nil }
        guard pasteboard.types?.contains(.string) == true,
              let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text.trimmingCharacters(in: .newlines)
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { "> \($0)" }
            .joined(separator: "\n") + "\n\n"
    }

    private var pasteboardMonitor: Timer?

    /// 常驻只观察 changeCount 以判断文字新鲜度，不提前读取剪贴板内容。
    private func startPasteboardMonitor() {
        guard pasteboardMonitor == nil else { return }
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.observePasteboardChange()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pasteboardMonitor = timer
    }

    @discardableResult
    private func preserveDraft() -> Bool {
        guard session.state.hasPreparedDraft, !isHidingPanel else { return true }
        synchronizeEditorInput()
        session.send(.preserveDraft)
        return session.state.lastEventSucceeded
    }

    private func hideRecordPanel(submitted: Bool = false, keepingExternalFocus: Bool = false,
                                completion: @escaping @MainActor () -> Void = {}) {
        session.send(.externalFocusChanged)
        guard let panel = recordPanel, !isHidingPanel else { return }
        pendingGettingStarted = nil
        appState.cancelRecordShortcutTrial()
        let returnToWork = submitted && panel.isVisible && returnsToWorkAfterWelcome
        returnsToWorkAfterWelcome = false
        if keepingExternalFocus {
            // No delayed orderOut or activation after the destination has taken the foreground.
            isHidingPanel = true
            panel.hideForApplicationLaunch()
            isHidingPanel = false
            completion()
            return
        }
        guard panel.isVisible || submitted else {
            completion()
            return
        }
        isHidingPanel = true
        let finish: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.isHidingPanel = false
            // 主动启动或阅读设置可能激活 Jotway；欢迎已关闭，提交后由系统归还原工作焦点。
            if returnToWork, NSApp.isActive {
                NSApp.hide(nil)
                NSApp.unhideWithoutActivation()
            }
            completion()
        }
        if submitted {
            panel.animateSubmissionOut(effect: appState.submissionEffect, completion: finish)
        } else {
            panel.animateOut(completion: finish)
        }
    }

    func openGettingStarted(_ open: @escaping () -> Void,
                            activate: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) }) {
        guard editorFocusTarget.textView?.hasMarkedText() != true else {
            pendingGettingStarted = { [weak self] in self?.openGettingStarted(open, activate: activate) }
            return
        }
        // 帮助只在设置阅读；编辑窗口暂时让位，不暂存、切换记录或改动选区。
        pendingGettingStarted = nil
        beginGettingStarted()
        appState.gettingStartedRequest += 1
        open()
        activate()
    }

    func closeGettingStarted(cancelShortcutTrial: Bool = true) {
        pendingGettingStarted = nil
        session.send(.readingGettingStartedChanged(false))
        if cancelShortcutTrial { appState.cancelRecordShortcutTrial() }
    }

    func beginGettingStarted() {
        guard editorFocusTarget.textView?.hasMarkedText() != true else { return }
        session.send(.readingGettingStartedChanged(true))
        preservesEditorAfterGettingStarted = session.state.hasPreparedDraft
        if let panel = recordPanel {
            panel.hideForGettingStarted()
            isHidingPanel = false
        }
    }

    func showRecordFromGettingStarted() {
        if focusActionSetupIfNeeded() { return }
        guard editorFocusTarget.textView?.hasMarkedText() != true else { return }
        closeGettingStarted(cancelShortcutTrial: false)
        if let panel = recordPanel, session.state.hasPreparedDraft {
            panel.cancelSubmissionAnimation()
            isHidingPanel = false
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            panel.makeKey()
            panel.makeFirstResponder(editorFocusTarget.textView)
            preservesEditorAfterGettingStarted = false
        } else {
            showRecordPanel()
        }
    }
}

/// SwiftUI 内容变化后合并一次尺寸报告，避免在 AppKit 正在布局时递归调整窗口。
@MainActor
private final class ActionSetupHostingView: NSHostingView<AnyView> {
    var onPreferredSizeChange: ((NSSize) -> Void)?
    private var sizeReportScheduled = false

    override func layout() {
        super.layout()
        scheduleSizeReport()
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        scheduleSizeReport()
    }

    private func scheduleSizeReport() {
        guard !sizeReportScheduled else { return }
        sizeReportScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sizeReportScheduled = false
            guard let onPreferredSizeChange = self.onPreferredSizeChange else { return }
            onPreferredSizeChange(self.fittingSize)
        }
    }
}
