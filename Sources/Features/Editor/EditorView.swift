import AppKit
import KeyboardShortcuts
import SwiftUI

/// AppKit 编辑器与窗口之间的焦点、组词和用户事件桥接。
@MainActor @Observable
final class EditorFocusTarget {
    @ObservationIgnored weak var textView: NSTextView?
    @ObservationIgnored var preserveSelectionOnNextFocus = false
}

/// 记录面板的编辑器：唤起即空白卡片，直奔输入。
/// 默认 Enter 提交、Shift+Enter 换行；Esc 暂存并关闭。
/// SwiftUI TextEditor 在非激活面板内焦点/按键不可靠，按文档预案回退为
/// NSViewRepresentable 包 NSTextView（顺带解决 IME 组词中回车误触保存的问题）。
private struct LauncherTotalHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct LauncherInputCardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct EditorView: View {
    @Binding var text: String
    var appState: AppState? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let focusTarget: EditorFocusTarget
    let state: LauncherViewState
    let send: (LauncherEvent) -> Void
    /// 内容尺寸变化上报（总高、输入卡高），窗口据此顶锚定改高
    var onContentSizeChange: (CGFloat, CGFloat) -> Void = { _, _ in }

    /// placeholder 单点定义（EditorTextView 的默认值也引用这里）。
    static var placeholderText: String { L10n.text("launcher.placeholder") }

    @State private var editorTextHeight: CGFloat = LauncherMetrics.editorMinHeight
    @State private var reportedTotalHeight: CGFloat = 0
    @State private var reportedCardHeight: CGFloat = 0
    /// 同一轮布局里总高与卡高两个 preference 会先后到达，合并为一次上报，避免窗口收两帧几何。
    @State private var geometryReportScheduled = false

    var body: some View {
        let stack = VStack(spacing: LauncherMetrics.cardGap) {
            inputCard
            if isOverlayVisible {
                overlayCard
                    .transition(overlayTransition)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(overlayAnimation, value: isOverlayVisible)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: LauncherTotalHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(LauncherTotalHeightKey.self) { total in
            reportedTotalHeight = total
            scheduleGeometryReport()
        }
        .onPreferenceChange(LauncherInputCardHeightKey.self) { card in
            reportedCardHeight = card
            scheduleGeometryReport()
        }
        // 材质和描边只响应外观，状态切换不改变卡片轮廓。
        stack
            .frame(maxHeight: .infinity, alignment: .top)
    }

    private var overlayAnimation: Animation {
        .easeOut(duration: reduceMotion ? LauncherMetrics.reducedMotionDuration : LauncherMetrics.overlayAppearDuration)
    }

    /// 合并同一轮布局里的几何上报：总高与卡高到齐后只通知窗口一次。
    private func scheduleGeometryReport() {
        guard !geometryReportScheduled else { return }
        geometryReportScheduled = true
        DispatchQueue.main.async {
            geometryReportScheduled = false
            onContentSizeChange(reportedTotalHeight, reportedCardHeight)
        }
    }

    /// 悬浮层只快速淡入淡出：不做位移动画，窗口改高也是瞬时的，画面零抖动。
    private var overlayTransition: AnyTransition {
        .opacity
    }

    /// 悬浮层只挂动作目标选择器（普通输入的动作与摘要已收进输入卡动作行）。
    private var isOverlayVisible: Bool {
        if state.isReadingGettingStarted { return false }
        return state.isIntentCandidateMenuVisible
    }

    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 0.38, green: 0.76, blue: 1)
            : Color(red: 0.10, green: 0.34, blue: 0.72)
    }

    private var cardSurface: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.10, green: 0.14, blue: 0.20), Color(red: 0.055, green: 0.08, blue: 0.12)]
                : [Color(red: 0.97, green: 0.98, blue: 1), Color(red: 0.91, green: 0.94, blue: 0.98)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// 冷色实底稳定正文对比，少量原生材质保留环境层次；降低透明度时使用完全实色。
    private func cardChrome<Content: View>(_ content: Content, cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // 圆角之外保持透明；外扩阴影在浅色桌面上会形成一圈灰底。
        return content
            .background(WindowDragHandle()) // 拖拽只挂在非文本区域。
            .background {
                ZStack {
                    if !reduceTransparency { shape.fill(.regularMaterial) }
                    shape.fill(cardSurface)
                        .opacity(reduceTransparency || colorSchemeContrast == .increased ? 1 : 0.94)
                }
                .allowsHitTesting(false)
            }
            .overlay { cardOutline(shape) }
    }

    private func cardOutline(_ shape: RoundedRectangle) -> some View {
        shape
            .strokeBorder(
                LinearGradient(
                    colors: colorSchemeContrast == .increased
                        ? [Color.primary.opacity(0.70), Color.primary.opacity(0.45)]
                        : [accent.opacity(colorScheme == .dark ? 0.48 : 0.30),
                           Color.primary.opacity(0.09), accent.opacity(0.18)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
            )
            .allowsHitTesting(false)
    }

    private var editorHeight: CGFloat {
        min(max(editorTextHeight, LauncherMetrics.editorMinHeight), LauncherMetrics.editorMaxHeight)
    }

    private var inputCard: some View {
        cardChrome(
            VStack(spacing: LauncherMetrics.cardInnerGap) {
                EditorTextViewRepresentable(
                    text: $text,
                    focusTarget: focusTarget,
                    state: state,
                    send: send,
                    placeholder: Self.placeholderText,
                    onContentHeightChange: { editorTextHeight = $0 }
                )
                .frame(height: editorHeight)
                actionRow
            }
            .padding(.horizontal, LauncherMetrics.cardPaddingH)
            .padding(.vertical, LauncherMetrics.cardPaddingV)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: LauncherInputCardHeightKey.self, value: proxy.size.height)
                }
            ),
            cornerRadius: LauncherMetrics.inputCardCornerRadius
        )
    }

    // MARK: - D2 动作行（固定 28pt，始终占位）

    /// 状态行文字的优先级：阻断性失败 > 明确用户操作反馈 > 识别中提示。
    /// 动作摘要已下线——目标由右侧动作标签单一承载，不再与「存到备忘录」重复叙述。
    private var actionRowStatusText: String? {
        if let message = state.message { return message }
        if let trial = appState?.shortcutTrialMessage { return trial }
        if let status = state.intentStatus { return status }
        if let issue = state.intentIssue { return issue }
        return nil
    }

    /// 动作行：反馈/状态（单行尾省略，靠左）→ 弹性空间 → 确定性动作标签（靠右，点击 = Enter）。
    private var actionRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if let status = actionRowStatusText {
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1) // 窄窗口先压反馈
                    .help(status)
                    .accessibilityLabel(status)
                    .accessibilityAddTraits(.updatesFrequently)
                    .padding(.bottom, 1) // 与动作标签基线对齐
            }
            Spacer(minLength: 0)
            actionTarget
        }
        // 下端对齐：动作标签贴着动作行下缘，视觉更沉稳。
        .frame(height: LauncherMetrics.actionRowHeight, alignment: .bottom)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 当前是否处于「选择器打开」状态：此时动作标签禁用，键盘由选择器接管。
    private var isAnySelectorVisible: Bool {
        state.isIntentCandidateMenuVisible
    }

    @ViewBuilder
    private var actionTarget: some View {
        if let title = state.displayedActionTitle, !state.isReadingGettingStarted {
            primaryActionLabel(title: title)
        }
        // 空草稿：动作标签留白，动作行容器仍占位（28pt）。
    }

    /// 冷蓝动作按钮与独立回车键帽强化可执行目标；点击与 Enter 共用同一路由解析。
    /// ⌥↑/⌥↓ 在有多个目标时切换（无图标提示，切换说明落在 tooltip）。
    private func primaryActionLabel(title: String) -> some View {
        Button { send(.confirm(.button)) } label: {
            HStack(spacing: 5) {
                if state.intentDeviated {
                    // 已偏离 Jev 建议：●，提示这是用户改过的目标。
                    Circle().fill(accent).frame(width: 5, height: 5)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text("↵")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .frame(width: 16, height: 16)
                    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 3))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(accent.opacity(0.24), lineWidth: 0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent)
        .disabled(isAnySelectorVisible)
        .opacity(isAnySelectorVisible ? 0.45 : 1)
        .accessibilityIdentifier("jev-confirm-intent")
        .help(actionTargetHelp)
    }

    /// 动作标签的 tooltip：常态说明执行键；可切换时补上 ⌥↑/⌥↓（替代被撤下的展开图标）。
    private var actionTargetHelp: String {
        if state.intentDeviated {
            return state.intentCanCycle ? L10n.text("launcher.target_help.changed_cycle")
                : L10n.text("launcher.target_help.changed")
        }
        return state.intentCanCycle ? L10n.text("launcher.target_help.execute_cycle")
            : L10n.text("launcher.target_help.execute")
    }

    private var overlayCard: some View {
        cardChrome(intentCandidateMenuContent, cornerRadius: LauncherMetrics.overlayCornerRadius)
    }

    /// D2：候选目标选择器卡——只有用户主动展开才出现；点击行只选定目标，不执行。
    private var intentCandidateMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(state.intentCandidates) { candidate in
                Button {
                    send(.selectTarget(candidate.id))
                    send(.candidateMenuChanged(false))
                } label: {
                    HStack(spacing: 6) {
                        Text(candidate.title)
                        Spacer(minLength: 8)
                        if candidate.isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(candidate.isSelected ? accent.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("launcher.switch_target", candidate.title))
            }
            HStack {
                Spacer(minLength: 8)
                keyHint("⏎", L10n.text("launcher.select"))
                keyHint("esc", L10n.text("launcher.collapse"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .padding(6)
    }

    private func keyHint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(action)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 拖拽把手

/// 提示条区域的拖拽把手：mouseDown 直接转交窗口拖动。
/// 编辑区保留给文本选择（NSTextView 自己消费拖拽），底部条是天然的拖动区域。
/// acceptsFirstResponder = false：拖动不会抢走编辑器焦点，也不会误触发失焦暂存。
/// 两处自动提示共用实际窗口可见判定；隐藏预建、离屏渲染和被遮挡窗口不消费机会。
struct HintPresentation: NSViewRepresentable {
    let onVisible: () -> Void

    func makeNSView(context: Context) -> VisibilityView { VisibilityView() }
    func updateNSView(_ view: VisibilityView, context: Context) {
        view.onVisible = onVisible
        view.checkPresentation()
    }

    final class VisibilityView: NSView {
        var onVisible: (() -> Void)?
        private(set) var didReport = false
        private var observers: [NSObjectProtocol] = []
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.checkPresentation() }
                })
            }
            checkPresentation()
        }

        override func layout() { super.layout(); checkPresentation() }
        override func draw(_ dirtyRect: NSRect) { checkPresentation() }

        func checkPresentation() {
            guard !didReport else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.didReport, let window = self.window,
                      window.isVisible, window.occlusionState.contains(.visible), window.alphaValue > 0,
                      !self.isHiddenOrHasHiddenAncestor, !self.visibleRect.isEmpty else { return }
                self.didReport = true
                self.onVisible?()
            }
        }

        isolated deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowDragNSView: NSView {
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        // performWindowDragWithEvent: 未导入 Swift，用经典手动拖动循环（纯公开 API）
        guard let window else { return }
        let originStart = window.frame.origin
        let mouseStart = NSEvent.mouseLocation
        let recordPanel = window as? RecordPanel
        defer { recordPanel?.endUserDrag() }
        while true {
            guard let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .default,
                dequeue: true
            ) else { break }
            if next.type == NSEvent.EventType.leftMouseUp { break }
            let mouse = NSEvent.mouseLocation
            let origin = NSPoint(
                x: originStart.x + mouse.x - mouseStart.x,
                y: originStart.y + mouse.y - mouseStart.y
            )
            if let recordPanel {
                recordPanel.beginUserDrag()
                recordPanel.moveForUserDrag(to: origin)
            } else {
                window.setFrameOrigin(origin)
            }
        }
    }
}

// MARK: - NSTextView 封装

private struct EditorTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    let focusTarget: EditorFocusTarget
    let state: LauncherViewState
    let send: (LauncherEvent) -> Void
    let placeholder: String
    /// 文本排版高度变化上报（输入卡自动长高用；宽度变化、内容变化都会触发）。
    let onContentHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, send: send)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.focusRingType = .none // 去掉聚焦时输入框四周的蓝色描边
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = EditorTextView(usingTextLayoutManager: true)
        textView.focusRingType = .none
        textView.delegate = context.coordinator
        textView.focusTarget = focusTarget
        textView.state = state
        textView.send = send
        textView.placeholder = placeholder
        textView.onContentHeightChange = onContentHeightChange
        textView.font = NSFont.systemFont(ofSize: 15) // 15pt：指令输入不抢眼，多行备忘也清爽
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = LauncherMetrics.editorLineSpacing
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes[.paragraphStyle] = paragraphStyle
        textView.textColor = .labelColor
        textView.insertionPointColor = NSColor(name: "JotwayInsertionPoint") { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 0.38, green: 0.76, blue: 1, alpha: 1)
                : NSColor(srgbRed: 0.10, green: 0.34, blue: 0.72, alpha: 1)
        }
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = .zero // 内边距由输入卡统一承担（16/14）
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        focusTarget.textView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EditorTextView else { return }
        textView.focusTarget = focusTarget
        textView.state = state
        textView.send = send
        textView.placeholder = placeholder
        textView.onContentHeightChange = onContentHeightChange
        context.coordinator.send = send
        textView.setPlainText(text, reason: .synchronize)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var send: (LauncherEvent) -> Void
        weak var textView: EditorTextView?

        init(text: Binding<String>, send: @escaping (LauncherEvent) -> Void) {
            _text = text
            self.send = send
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? EditorTextView else { return }
            text = textView.string
        }

        /// 点到面板内非输入区 → 编辑器失焦 → 自动暂存草稿（§10.1）
        func textDidEndEditing(_ notification: Notification) {
            send(.preserveDraft)
        }
    }
}

/// 按键语义：依当前偏好换行或提交 / Esc 取消；↑/↓ 翻阅由面板层 key monitor 统一接管。
/// IME 组词（有 marked text）期间一律放行，由输入法和系统默认行为处理。
/// placeholder 直接在 draw 里画，不经过 SwiftUI——面板侧 binding 不是
/// @Observable，SwiftUI 不会因打字触发重渲染。
final class EditorTextView: NSTextView {
    weak var focusTarget: EditorFocusTarget?
    var state: LauncherViewState!
    var send: (LauncherEvent) -> Void = { _ in }
    var placeholder = EditorView.placeholderText {
        didSet { if placeholder != oldValue { needsDisplay = true } }
    }
    /// 文本排版高度变化上报（输入卡自动长高用）。
    var onContentHeightChange: ((CGFloat) -> Void)?

    private var suppressesIntentReturnRepeats = false
    private var observesUndo = false
    private var lastReportedText = ""

    enum ReplacementReason {
        case synchronize
        case restoreDraft
        case newDraft
    }

    /// 程序化替换正文；组词中拒绝且不改变编辑状态。用户输入仍走原生编辑与 delegate。
    /// 新草稿身份由调用方判断：正文相同的新草稿也必须重置撤销边界。
    @discardableResult
    func setPlainText(_ text: String, reason: ReplacementReason = .synchronize) -> Bool {
        guard !hasMarkedText() else { return false }
        observeUndoChangesIfNeeded()
        let contentChanged = string != text
        if reason == .newDraft {
            breakUndoCoalescing()
            undoManager?.removeAllActions()
        }
        guard contentChanged || reason != .synchronize else { return true }
        if contentChanged {
            string = text
        }
        if reason == .newDraft {
            breakUndoCoalescing()
            undoManager?.removeAllActions()
        }
        if reason != .synchronize {
            setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
        }
        updatePlaceholderVisibility()
        reportContentHeight()
        lastReportedText = string
        needsDisplay = true
        return true
    }

    /// 粘贴与拖放只接收文字。富文本降级为字符，附件占位符被移除；图片和文件不写入正文。
    @discardableResult
    func insertPlainText(from pasteboard: NSPasteboard) -> Bool {
        guard !hasMarkedText(), pasteboard.types?.contains(.fileURL) != true,
              let text = plainText(from: pasteboard), !text.isEmpty else { return false }
        breakUndoCoalescing()
        insertText(text, replacementRange: selectedRange())
        breakUndoCoalescing()
        return true
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.string, .rtfd, .rtf, .html]
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        [.string, .rtfd, .rtf, .html]
    }

    override func readSelection(from pasteboard: NSPasteboard) -> Bool {
        insertPlainText(from: pasteboard)
    }

    override func readSelection(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        insertPlainText(from: pasteboard)
    }

    private func plainText(from pasteboard: NSPasteboard) -> String? {
        if let text = pasteboard.string(forType: .string) { return text }
        let attributed: NSAttributedString?
        if let data = pasteboard.data(forType: .rtfd) {
            attributed = NSAttributedString(rtfd: data, documentAttributes: nil)
        } else if let data = pasteboard.data(forType: .rtf) {
            attributed = NSAttributedString(rtf: data, documentAttributes: nil)
        } else if let data = pasteboard.data(forType: .html) {
            attributed = NSAttributedString(html: data, documentAttributes: nil)
        } else {
            attributed = nil
        }
        return attributed?.string.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    /// 输入卡自动长高：上报当前排版高度（不含卡片内边距，由 SwiftUI 侧加回）。
    func reportContentHeight() {
        guard let onContentHeightChange, let textLayoutManager else { return }
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        let height = ceil(textLayoutManager.usageBoundsForTextContainer.height)
        onContentHeightChange(height)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // 宽度变化会改变折行，高度随之变；上报幂等（SwiftUI 侧同值不触发更新）。
        reportContentHeight()
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        updatePlaceholderVisibility()
        send(.compositionChanged(hasMarkedText()))
    }

    override func unmarkText() {
        super.unmarkText()
        updatePlaceholderVisibility()
        send(.compositionChanged(hasMarkedText()))
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        send(.compositionChanged(true))
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        updatePlaceholderVisibility()
        send(.compositionChanged(hasMarkedText()))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard placeholderAlpha > 0.01 else { return }
        // 保留语义颜色对主题和玻璃材质的适配；淡入淡出单独作用于绘制透明度。
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.cgContext.setAlpha(placeholderAlpha)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.placeholderTextColor,
            .paragraphStyle: defaultParagraphStyle ?? NSParagraphStyle.default,
        ]
        let linePadding = textContainer?.lineFragmentPadding ?? 0
        let origin = NSPoint(
            x: textContainerInset.width + linePadding,
            y: textContainerInset.height
        )
        NSAttributedString(string: placeholder, attributes: attributes)
            .draw(at: origin)
    }

    // MARK: - Placeholder 淡入淡出

    private var placeholderAlpha: CGFloat = 1
    private var placeholderTarget: CGFloat = 1
    private var placeholderTimer: Timer?

    /// placeholder 随「有无内容」0.15s 淡入淡出，避免打字瞬间生硬闪现。
    private func updatePlaceholderVisibility() {
        let target: CGFloat = (string.isEmpty && !hasMarkedText()) ? 1 : 0
        guard target != placeholderTarget else { return }
        placeholderTarget = target
        placeholderTimer?.invalidate()
        let from = placeholderAlpha
        let start = CFAbsoluteTimeGetCurrent()
        let duration: CFAbsoluteTime = 0.15
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let p = CGFloat(min((CFAbsoluteTimeGetCurrent() - start) / duration, 1))
                self.placeholderAlpha = from + (target - from) * p
                self.needsDisplay = true
                if p >= 1 {
                    self.placeholderTimer?.invalidate()
                    self.placeholderTimer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        placeholderTimer = timer
    }

    override func didChangeText() {
        super.didChangeText()
        observeUndoChangesIfNeeded()
        lastReportedText = string
        updatePlaceholderVisibility()
        reportContentHeight()
    }

    private func observeUndoChangesIfNeeded() {
        guard !observesUndo else { return }
        observesUndo = true
        lastReportedText = string
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(undoFinished), name: name, object: nil)
        }
    }

    @objc private func undoFinished(_ notification: Notification) {
        guard notification.object as? UndoManager === undoManager, string != lastReportedText else { return }
        didChangeText()
    }

    isolated deinit { NotificationCenter.default.removeObserver(self) }

    override func keyDown(with event: NSEvent) {
        // 非激活面板下 app 不激活，主菜单 key equivalent 路由（Cmd+C/V/X/A/Z）不可用：
        // 菜单匹配失败后事件穿透到 keyDown，若不接手则整组编辑快捷键全断。
        // 这里手动派发到对应动作。
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command), !hasMarkedText() {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "v":
                paste(self)
                return
            case "c":
                copy(self)
                return
            case "x":
                cut(self)
                return
            case "a":
                selectAll(nil)
                return
            case "z":
                if mods.contains(.shift) { undoManager?.redo() } else { undoManager?.undo() }
                return
            default:
                break
            }
        }
        guard !hasMarkedText() else {
            super.keyDown(with: event)
            return
        }

        let isReturn = event.keyCode == 0x24 || event.keyCode == 0x4C // 回车 / 小键盘回车
        let returnModifiers = mods.intersection([.command, .control, .option, .shift])
        if isReturn, event.isARepeat, suppressesIntentReturnRepeats { return }
        if !event.isARepeat { suppressesIntentReturnRepeats = false }
        if isReturn, returnModifiers == .command, focusTarget != nil,
           state.isIntentRecognitionEnabled,
           !state.isIntentCandidateMenuVisible,
           !state.isReadingGettingStarted {
            if !event.isARepeat { send(.confirm(.commandEnter)) }
            return // Never submit a record or queue a future action while recognition is pending.
        }
        // D2：候选目标菜单打开时键盘由选择器接管——↑↓ 切换、Enter 只选定不执行、Esc 收起。
        if focusTarget != nil, state.isIntentCandidateMenuVisible {
            if event.keyCode == 0x35 { // Esc 先收选择器
                send(.candidateMenuChanged(false))
                return
            }
            if returnModifiers.isEmpty, event.keyCode == 0x7E || event.keyCode == 0x7D {
                if !event.isARepeat { send(.cycleTarget(forward: event.keyCode == 0x7D)) } // 0x7D=下=forward
                return
            }
            if isReturn, returnModifiers.isEmpty {
                if !event.isARepeat { send(.candidateMenuChanged(false)) }
                return
            }
        }
        // ⌥↑/⌥↓：在 Jev 建议与其他可用目标间切换（仅当有多个目标可切换时拦截）。
        if focusTarget != nil, state.intentCanCycle,
           state.isIntentRecognitionEnabled,
           !state.isReadingGettingStarted,
           returnModifiers == .option, event.keyCode == 0x7E || event.keyCode == 0x7D {
            if !event.isARepeat { send(.cycleTarget(forward: event.keyCode == 0x7D)) } // 0x7D=下=forward
            return
        }
        if isReturn, returnModifiers.isEmpty || returnModifiers == .shift {
            if returnModifiers == .shift {
                insertNewline(nil) // 原生编辑：替换选区并支持撤销
                return
            }
            // ⏎ 永远执行当前目标，不区分识别是否已落地。
            if focusTarget != nil, state.isIntentRecognitionEnabled {
                suppressesIntentReturnRepeats = true
                if !event.isARepeat { send(.confirm(.enter)) }
                return
            }
        }
        if event.keyCode == 0x35 { // Esc
            guard !event.isARepeat else { return }
            send(.cancel)
            return
        }
        super.keyDown(with: event)
    }
}
