import AppKit
import QuartzCore
import SwiftUI

enum SubmissionEffect: String, CaseIterable {
    case wind, ufo

    var title: String {
        self == .wind ? L10n.text("submission_effect.wind") : L10n.text("submission_effect.ufo")
    }
    var duration: TimeInterval { self == .wind ? 0.50 : 0.32 }
}

/// 记录面板：非激活闪现窗口。
/// 系统层 active app 不变；面板隐藏后键盘焦点无缝回到原应用。
/// ↑/↓ 由面板层 local key monitor 统一接管（§10.2）：
/// 编辑器有焦点且有内容时放行（默认光标移动），其余情况消费为历史翻阅。
@MainActor
final class RecordPanel: NSPanel, NSWindowDelegate {
    static let cornerRadius = LauncherMetrics.inputCardCornerRadius
    let edgeGlow = RecordPanelGlowView(frame: .zero)
    private let text: Binding<String>
    private weak var appState: AppState?
    private let focusTarget: EditorFocusTarget
    private let state: LauncherViewState
    private let send: (LauncherEvent) -> Void
    private var keyMonitor: Any?
    /// 手动拖过的高度（§3.3 手动拖拽优先）：本会话内自动长高让位，重新唤起恢复。
    private var manualContentHeight: CGFloat?
    /// 最近一次上报的输入卡高度（提交特效按双卡轮廓合成截图用）。
    private var lastInputCardHeight: CGFloat = LauncherMetrics.inputCardMinHeight
    private(set) var submissionAnimationWindow: NSPanel?
    private var hideAnimationTask: Task<Void, Never>?
    private var isAdjustingFrame = false
    private var presentationScreen: RecordPanelPlacement.Screen?
    private var dragStartOrigin: CGPoint?
    private var draggedFrame: CGRect?
    private var dragEndMonitor: Any?

    override var canBecomeKey: Bool { true }

    init(
        appState: AppState? = nil,
        text: Binding<String>,
        focusTarget: EditorFocusTarget,
        state: LauncherViewState,
        send: @escaping (LauncherEvent) -> Void
    ) {
        self.text = text
        self.appState = appState
        self.focusTarget = focusTarget
        self.state = state
        self.send = send
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: LauncherMetrics.panelWidth, height: LauncherMetrics.inputCardMinHeight),
            styleMask: [.borderless, .nonactivatingPanel, .resizable], // borderless + resizable：系统照样给四边拖拽调整
            backing: .buffered,
            defer: false
        )
        contentMinSize = NSSize(width: 360, height: LauncherMetrics.inputCardMinHeight)
        contentMaxSize = NSSize(width: 1200, height: LauncherMetrics.inputCardMaxHeight + LauncherMetrics.cardGap + 280)
        delegate = self
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // 卡片圆角外保持透明，不叠加系统窗口阴影。
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        let hostingView = NSHostingView(
            rootView: EditorView(
                text: text,
                appState: appState,
                focusTarget: focusTarget,
                state: state,
                send: send,
                onContentSizeChange: { [weak self] totalHeight, cardHeight in
                    // 等本轮 SwiftUI 布局完成再缩放，否则按键事件中内容可能重复伸缩。
                    DispatchQueue.main.async { [weak self] in
                        self?.contentSizeDidChange(totalHeight: totalHeight, inputCardHeight: cardHeight)
                    }
                }
            )
        )
        hostingView.sizingOptions = [] // 窗口负责尺寸限制，内容只跟随可用宽高
        // 双卡结构（§3.1）：窗口透明无材质，输入卡与悬浮层各自持有玻璃/回退材质。
        // contentView 用独立容器而非 hostingView 本体：NSHostingView 会把渲染子视图
        // 插到最上层，直接当 contentView 会把 edgeGlow 压在 SwiftUI 内容下面。
        let container = NSView(frame: NSRect(
            x: 0, y: 0, width: LauncherMetrics.panelWidth, height: LauncherMetrics.inputCardMinHeight))
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        edgeGlow.frame = container.bounds
        edgeGlow.autoresizingMask = [.width, .height]
        container.addSubview(edgeGlow, positioned: .above, relativeTo: nil)
        contentView = container
        installKeyMonitor()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(reduceMotionChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
    }

    isolated deinit {
        hideAnimationTask?.cancel()
        submissionAnimationWindow?.close()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let dragEndMonitor { NSEvent.removeMonitor(dragEndMonitor) }
    }

    override func close() {
        cancelUserDrag()
        send(.panelDismissed)
        appState?.cancelRecordShortcutTrial()
        edgeGlow.stop()
        cancelSubmissionAnimation()
        super.close()
    }

    override func orderOut(_ sender: Any?) {
        cancelUserDrag()
        send(.panelDismissed)
        appState?.cancelRecordShortcutTrial()
        edgeGlow.stop()
        super.orderOut(sender)
    }

    /// 应用启动交给系统前同步隐藏，旧退场任务不能再干预后续窗口。
    func hideForApplicationLaunch() {
        cancelSubmissionAnimation()
        edgeGlow.stop()
        orderOut(nil)
        if let origin = preFadeOrigin { setFrameOrigin(origin); preFadeOrigin = nil }
        alphaValue = 1
    }

    /// 浮动记录窗口给设置帮助让位，保留编辑器、选区与历史现场。
    func hideForGettingStarted() {
        cancelSubmissionAnimation()
        edgeGlow.stop()
        super.orderOut(nil)
        if let origin = preFadeOrigin { setFrameOrigin(origin); preFadeOrigin = nil }
        alphaValue = 1
    }

    override func becomeKey() {
        super.becomeKey()
        send(.panelPresented)
        if isVisible { edgeGlow.start(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
    }

    /// 切走到别的 app → 面板失焦：自动暂存草稿（§10.1），但**不关闭**面板（键盘流约定）。
    override func resignKey() {
        edgeGlow.stop()
        super.resignKey()
        send(.externalFocusChanged)
        send(.preserveDraft)
    }

    /// 每次唤起先选屏，再恢复该屏位置；显示期间不再跟随鼠标。
    func showPanel() {
        manualContentHeight = nil // 重新唤起恢复自动长高（§3.3）
        if !isVisible {
            // 离屏先完成一轮布局：草稿文本、卡片高度上报与改高都在显示前落地，
            // 避免面板出现后再被看见长个（appear 期间的残留尺寸变化由下方 alpha 门槛兜住）。
            contentView?.layoutSubtreeIfNeeded()
            positionForPresentation(in: RecordPanelPlacement.screens, cursor: NSEvent.mouseLocation,
                fallbackID: NSScreen.main.map { RecordPanelPlacement.snapshot($0).id })
        }
        orderFrontRegardless()
        makeKey()
        animateIn()
        contentView?.layoutSubtreeIfNeeded()
        focusTextEditor()
        // 仅在编辑器尚未创建或尚未取得焦点时重试，避免再次移动刚设置的光标。
        if focusTarget.textView == nil || firstResponder !== focusTarget.textView {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isVisible, self.isKeyWindow,
                      self.focusTarget.textView == nil || self.firstResponder !== self.focusTarget.textView else { return }
                self.focusTextEditor()
            }
        }
    }

    /// 与真实唤起共用，允许用合成显示器离屏验证选屏和偏好恢复。
    func positionForPresentation(in screens: [RecordPanelPlacement.Screen], cursor: CGPoint, fallbackID: String? = nil) {
        guard !isVisible else { return }
        guard let target = RecordPanelPlacement.targetScreen(in: screens, cursor: cursor,
            followsCursor: appState?.recordPanelFollowsCursor ?? true, fallbackID: fallbackID) else { return }
        presentationScreen = target
        adjustingFrame {
            constrainSize(to: target.visibleFrame)
            setFrameOrigin(RecordPanelPlacement.origin(for: frame.size, on: target,
                savedOffset: appState?.recordPanelOffset(on: target.id)))
        }
    }

    private func adjustingFrame(_ update: () -> Void) {
        let wasAdjusting = isAdjustingFrame
        isAdjustingFrame = true
        defer { isAdjustingFrame = wasAdjusting }
        update()
    }

    /// 保留本次运行的尺寸；换屏或显示器可用区域缩小时仅收敛越界部分。
    func constrainSize(to visibleFrame: NSRect, proposedFrame: NSRect? = nil) {
        guard visibleFrame.width >= 1, visibleFrame.height >= 1,
              [visibleFrame.minX, visibleFrame.minY, visibleFrame.width, visibleFrame.height].allSatisfy(\.isFinite) else { return }
        let margin = min(16, max(0, (visibleFrame.width - 44) / 2))
        let maximumWidth = min(1200, visibleFrame.width - margin * 2)
        let minimumWidth = min(360, maximumWidth)
        let maximumHeight = min(LauncherMetrics.inputCardMaxHeight + LauncherMetrics.cardGap + 280, visibleFrame.height)
        let minimumHeight = min(LauncherMetrics.inputCardMinHeight, maximumHeight)
        var constrained = proposedFrame ?? frame
        constrained.size.width = min(max(constrained.width, minimumWidth), maximumWidth)
        constrained.size.height = min(max(constrained.height, minimumHeight), maximumHeight)
        constrained.origin.x = min(max(constrained.minX, visibleFrame.minX + margin), visibleFrame.maxX - margin - constrained.width)
        constrained.origin.y = min(max(constrained.minY, visibleFrame.minY), visibleFrame.maxY - constrained.height)
        adjustingFrame {
            // 先放宽旧下限，再设置新边界；小屏切回大屏时也不产生 min > max。
            contentMinSize = NSSize(width: min(contentMinSize.width, minimumWidth),
                                    height: min(contentMinSize.height, minimumHeight))
            contentMaxSize = NSSize(width: maximumWidth, height: maximumHeight)
            contentMinSize = NSSize(width: minimumWidth, height: minimumHeight)
            if constrained != frame { setFrame(constrained, display: true) }
        }
    }

    /// 双卡内容尺寸变化：锚定输入卡顶边改窗高，瞬时完成（不做 resize 动画，用户明确不要画面抖动）。
    /// 手动拖拽优先：本会话内用户拖过高度后按手动值，重新唤起恢复自动（§3.3）。
    private func contentSizeDidChange(totalHeight: CGFloat, inputCardHeight: CGFloat) {
        if inputCardHeight > 0 { lastInputCardHeight = inputCardHeight }
        guard totalHeight > 0, !inLiveResize else { return }
        let target = min(max(manualContentHeight ?? totalHeight, contentMinSize.height), contentMaxSize.height)
        var resized = frame
        let delta = target - contentRect(forFrameRect: resized).height
        guard abs(delta) > 0.5 else { return }
        resized.size.height += delta
        resized.origin.y -= delta // 顶锚定：输入卡不动，悬浮层向下长
        if let target = presentationScreen ?? screen.map(RecordPanelPlacement.snapshot) {
            let minY = target.visibleFrame.minY
            if resized.origin.y < minY { resized.origin.y = minY } // 底部探出屏幕时顶回去
        }
        adjustingFrame {
            setFrame(resized, display: true, animate: false)
        }
    }

    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval {
        // 内容驱动的改高全部瞬时完成（contentSizeDidChange 传 animate: false）；
        // 此处仅兜底系统/手动路径，保持与面板进出动画一致的时长。
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? LauncherMetrics.reducedMotionDuration : LauncherMetrics.overlayAppearDuration
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        // 只认用户拖拽：setFrame(animate:) 的原生 resize 动画也会触发这对通知，不能当成手动值
        guard let event = NSApp.currentEvent, event.window === self,
              event.type == .leftMouseUp || event.type == .leftMouseDragged else { return }
        manualContentHeight = contentRect(forFrameRect: frame).height
    }

    func windowDidChangeScreen(_ notification: Notification) {
        // 搜索伸缩及动效可能触发此通知；只有手动跨屏才更新本次显示的目标。
        guard !isAdjustingFrame, dragStartOrigin != nil || inLiveResize, let screen else { return }
        presentationScreen = RecordPanelPlacement.snapshot(screen)
        constrainSize(to: screen.visibleFrame)
    }

    func windowWillMove(_ notification: Notification) {
        // 原生背景拖动与自有把手共用生命周期，不把任意 didMove 当成用户操作。
        guard !isAdjustingFrame, !inLiveResize, preFadeOrigin == nil,
              let event = NSApp.currentEvent, event.window === self,
              event.type == .leftMouseDown || event.type == .leftMouseDragged else { return }
        beginUserDrag()
    }

    func windowDidMove(_ notification: Notification) {
        guard dragStartOrigin != nil, !isAdjustingFrame, !inLiveResize else { return }
        draggedFrame = frame
        if NSEvent.pressedMouseButtons & 1 == 0 { endUserDrag() }
    }

    func beginUserDrag() {
        guard dragStartOrigin == nil else { return }
        dragStartOrigin = frame.origin
        draggedFrame = nil
        dragEndMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.endUserDrag()
            return event
        }
    }

    /// 自有把手明确标记每次移动；不依赖鼠标松开后可能延迟到达的窗口通知。
    func moveForUserDrag(to origin: CGPoint) {
        guard dragStartOrigin != nil else { return }
        adjustingFrame { setFrameOrigin(origin) }
        draggedFrame = frame
    }

    func endUserDrag(in screens: [RecordPanelPlacement.Screen] = RecordPanelPlacement.screens) {
        let start = dragStartOrigin
        let moved = draggedFrame
        cancelUserDrag()
        guard let moved, moved.origin != start,
              let target = RecordPanelPlacement.screen(containing: moved, in: screens) else { return }
        appState?.saveRecordPanelOffset(RecordPanelPlacement.offset(for: moved, on: target), on: target.id)
        presentationScreen = target
        constrainSize(to: target.visibleFrame)
    }

    private func cancelUserDrag() {
        dragStartOrigin = nil
        draggedFrame = nil
        if let dragEndMonitor { NSEvent.removeMonitor(dragEndMonitor) }
        dragEndMonitor = nil
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        if isVisible && isKeyWindow && occlusionState.contains(.visible) && preFadeOrigin == nil {
            edgeGlow.start(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        } else {
            edgeGlow.stop()
        }
    }

    @objc private func reduceMotionChanged(_ notification: Notification) {
        edgeGlow.setReducedMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        updateScreenConfiguration(in: RecordPanelPlacement.screens)
    }

    func updateScreenConfiguration(in screens: [RecordPanelPlacement.Screen]) {
        guard let target = screens.first(where: { $0.id == presentationScreen?.id })
            ?? RecordPanelPlacement.screen(containing: frame, in: screens)
            ?? RecordPanelPlacement.targetScreen(in: screens, cursor: .zero, followsCursor: false) else { return }
        cancelUserDrag()
        presentationScreen = target
        constrainSize(to: target.visibleFrame)
        if preFadeOrigin != nil { preFadeOrigin = frame.origin }
    }

    // MARK: - 动效（Spotlight/Raycast 唤出配方：淡入 + 轻微位移）

    /// 淡出代际：淡出动画进行中再唤起时，让旧的完成回调失效（防止被 orderOut）
    private var hideGeneration = 0
    /// 淡出前的锚点位置：淡出中被重新唤起时以此为终点，避免面板逐次上飘
    private var preFadeOrigin: NSPoint?

    /// 唤出：淡入 + 上浮 10pt，easeOutQuint 曲线，0.16s
    func animateIn(reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        cancelUserDrag()
        cancelSubmissionAnimation()
        let finalOrigin = preFadeOrigin ?? frame.origin
        preFadeOrigin = nil
        if isVisible && isKeyWindow { edgeGlow.start(reduceMotion: reduceMotion) }
        if !reduceMotion { setFrameOrigin(NSPoint(x: finalOrigin.x, y: finalOrigin.y - 10)) }
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduceMotion ? 0.10 : 0.16
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            animator().alphaValue = 1
            animator().setFrameOrigin(finalOrigin)
        }
    }

    /// 关闭：淡出 + 上飘 8pt，0.12s，结束后 orderOut 并复位透明度
    func animateOut(reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    completion: @escaping @MainActor () -> Void) {
        cancelUserDrag()
        hideGeneration += 1
        let generation = hideGeneration
        preFadeOrigin = frame.origin
        let duration = reduceMotion ? 0.10 : 0.12
        edgeGlow.stop(duration: duration)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
            if !reduceMotion { animator().setFrameOrigin(NSPoint(x: frame.origin.x, y: frame.origin.y + 8)) }
        }
        // 窗口隐藏/被遮挡时 AppKit 未必回调；沿用提交退场的可取消任务完成收尾。
        hideAnimationTask?.cancel()
        hideAnimationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            guard let self, self.hideGeneration == generation else { return }
            self.orderOut(nil)
            self.alphaValue = 1
            self.preFadeOrigin = nil
            self.hideAnimationTask = nil
            completion()
        }
    }

    /// 在编辑区清空之前保留本次画面。只缓存自己的视图，不截取其他应用或屏幕。
    /// 准备阶段不显示窗口，也可用于离屏验证；无法缓存时由退场路径直接关闭。
    func prepareSubmissionAnimation() {
        edgeGlow.stop()
        cancelSubmissionAnimation()
        guard let contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        // 双卡结构后 contentView 即宿主视图（无玻璃壳特判）；透明间隙在截图里保持透明。
        let snapshotView = contentView
        guard let bitmap = snapshotView.bitmapImageRepForCachingDisplay(in: snapshotView.bounds) else { return }
        snapshotView.cacheDisplay(in: snapshotView.bounds, to: bitmap)
        guard let captured = bitmap.cgImage,
              let context = CGContext(data: nil, width: captured.width, height: captured.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        // 一次合成正文、底色与圆角；所有碎片共享这张纹理，避免碎片变成透明文字或方角背景。
        // 双卡轮廓：输入卡（r20）在顶，悬浮层（r16）在下，中间 8pt 间隙保持透明。
        let bounds = CGRect(origin: .zero, size: frame.size)
        context.scaleBy(x: CGFloat(captured.width) / bounds.width, y: CGFloat(captured.height) / bounds.height)
        let inputCardHeight = min(lastInputCardHeight, bounds.height)
        let inputCardRect = CGRect(x: 0, y: bounds.height - inputCardHeight, width: bounds.width, height: inputCardHeight)
        context.addPath(CGPath(roundedRect: inputCardRect,
            cornerWidth: LauncherMetrics.inputCardCornerRadius, cornerHeight: LauncherMetrics.inputCardCornerRadius, transform: nil))
        let overlayHeight = bounds.height - inputCardHeight - LauncherMetrics.cardGap
        if overlayHeight > LauncherMetrics.cardGap {
            let overlayRect = CGRect(x: 0, y: 0, width: bounds.width, height: overlayHeight)
            context.addPath(CGPath(roundedRect: overlayRect,
                cornerWidth: LauncherMetrics.overlayCornerRadius, cornerHeight: LauncherMetrics.overlayCornerRadius, transform: nil))
        }
        context.clip()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        }
        context.fill(bounds)
        context.draw(captured, in: bounds)
        guard let image = context.makeImage() else { return }

        var animationFrame = frame.insetBy(dx: -96, dy: -56)
        if let screen { animationFrame = animationFrame.intersection(screen.frame) }
        let overlay = NSPanel(contentRect: animationFrame, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        overlay.isReleasedWhenClosed = false
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.level = level
        overlay.hidesOnDeactivate = false
        overlay.ignoresMouseEvents = true
        overlay.isExcludedFromWindowsMenu = true
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        overlay.animationBehavior = .none
        overlay.setAccessibilityElement(false)

        let container = NSView(frame: NSRect(origin: .zero, size: animationFrame.size))
        container.wantsLayer = true
        let snapshot = CALayer()
        snapshot.frame = frame.offsetBy(dx: -animationFrame.minX, dy: -animationFrame.minY)
        snapshot.contents = image
        snapshot.contentsScale = backingScaleFactor
        snapshot.allowsEdgeAntialiasing = true
        container.layer?.addSublayer(snapshot)
        overlay.contentView = container
        submissionAnimationWindow = overlay
    }

    /// 真实窗口立即隐藏并归还焦点；缓存画面按用户选择独立完成退场。
    func animateSubmissionOut(
        effect: SubmissionEffect = .wind,
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
        completion: @escaping @MainActor () -> Void
    ) {
        hideGeneration += 1
        let generation = hideGeneration
        let wasVisible = isVisible
        if wasVisible { submissionAnimationWindow?.orderFrontRegardless() }
        orderOut(nil)
        alphaValue = 1
        preFadeOrigin = nil
        guard let overlay = submissionAnimationWindow,
              let snapshot = overlay.contentView?.layer?.sublayers?.first else {
            cancelSubmissionAnimation()
            completion()
            return
        }

        let duration = reduceMotion ? 0.10 : effect.duration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if reduceMotion {
            addSubmissionAnimations([("opacity", [1.0, 0.0])], keyTimes: [0, 1], duration: duration, to: snapshot)
        } else {
            switch effect {
            case .wind: animateWind(snapshot, duration: duration)
            case .ufo: animateUFO(snapshot, duration: duration)
            }
        }
        CATransaction.commit()
        hideAnimationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(duration + 1.0 / 60)) } catch { return }
            guard let self, self.hideGeneration == generation else { return }
            self.submissionAnimationWindow?.close()
            self.submissionAnimationWindow = nil
            self.hideAnimationTask = nil
            completion()
        }
    }

    func cancelSubmissionAnimation() {
        hideGeneration += 1
        hideAnimationTask?.cancel()
        hideAnimationTask = nil
        submissionAnimationWindow?.close()
        submissionAnimationWindow = nil
    }

    // 对照 docs/assets/jotway-motion-directions.html 的 windPaper / ufoPaper。
    // 把同一进度公式采样成 Core Animation 关键帧，播放时不在主线程逐帧重绘。
    private func animateWind(_ snapshot: CALayer, duration: TimeInterval) {
        guard let container = snapshot.superlayer else { return }
        let size = snapshot.bounds.size
        // 原稿使用 5 pt 网格；大窗口按面积适当增大，限制层数并保持细碎颗粒。
        let cellSize = max(5, sqrt(size.width * size.height / 2200))
        let columns = max(2, Int(ceil(size.width / cellSize)))
        let rows = max(1, Int(ceil(size.height / cellSize)))
        let cellWidth = size.width / CGFloat(columns), cellHeight = size.height / CGFloat(rows)
        let progress = [0.0] + (0...8).map { Double($0) / 8 } + [1.0]
        let opacity: [Any] = progress.map { NSNumber(value: 1 - submissionSmooth(($0 - 0.18) / 0.82)) }
        addSubmissionAnimations([("opacity", [1.0, 0.5, 0.0, 0.0])],
            keyTimes: [0, 0.09, 0.18, 1], duration: duration, to: snapshot)
        for row in 0..<rows {
            for column in 0..<columns {
                let noise = sin(Double(column) * 127.1 + Double(row) * 311.7) * 43758.5453
                let flutterNoise = sin(Double(column) * 269.5 + Double(row) * 183.3) * 24634.6345
                let seed = noise - floor(noise), flutter = flutterNoise - floor(flutterNoise)
                let delay = (1 - Double(column) / Double(columns - 1)) * 0.54 + seed * 0.13
                let piece = CALayer()
                piece.name = "windParticle"
                piece.frame = CGRect(x: snapshot.frame.minX + CGFloat(column) * cellWidth,
                    y: snapshot.frame.maxY - CGFloat(row + 1) * cellHeight, width: cellWidth, height: cellHeight)
                piece.contents = snapshot.contents
                piece.contentsScale = snapshot.contentsScale
                piece.contentsRect = CGRect(x: CGFloat(column) / CGFloat(columns), y: 1 - CGFloat(row + 1) / CGFloat(rows),
                    width: 1 / CGFloat(columns), height: 1 / CGFloat(rows))
                piece.allowsEdgeAntialiasing = true
                container.addSublayer(piece)

                let travelTimes: [Double] = (0...8).map { delay + Double($0) / 8 * 0.33 }
                let times = [0.0] + travelTimes + [1.0]
                let positions = progress.map { p -> NSValue in
                    let drift = p * 0.7 + p * p * 0.3
                    let dx = (34 + seed * 46) * drift
                    // Canvas 的 y 轴向下，AppKit 的 y 轴向上；轨迹与旋转同时翻转。
                    let dy = (8 + flutter * 27) * p - sin(p * .pi * 2 + seed * .pi * 2) * p * 5
                    return NSValue(point: NSPoint(x: piece.position.x + dx, y: piece.position.y + dy))
                }
                let transforms = progress.map { p -> NSValue in
                    let scale = 1 - submissionSmooth(p) * 0.78
                    let rotation = CATransform3DMakeRotation(-(flutter - 0.5) * p * 2.2, 0, 0, 1)
                    return NSValue(caTransform3D: CATransform3DScale(rotation, scale,
                        scale * (1 - sin(p * .pi) * flutter * 0.35), 1))
                }
                addSubmissionAnimations([("position", positions), ("transform", transforms), ("opacity", opacity)],
                    keyTimes: times.map { NSNumber(value: $0) }, duration: duration, to: piece)
            }
        }
    }

    private func animateUFO(_ snapshot: CALayer, duration: TimeInterval) {
        guard let container = snapshot.superlayer else { return }
        let times = Array(Set((0...40).map { Double($0) / 40 } + [0.30, 0.46, 0.50, 0.72, 0.76, 0.82])).sorted()
        let keyTimes = times.map { NSNumber(value: $0) }
        let width = snapshot.bounds.width, height = snapshot.bounds.height
        let transforms = times.map { t -> NSValue in
            let compress = submissionSmooth(t / 0.46)
            return NSValue(caTransform3D: CATransform3DMakeScale(1 + 0.08 * compress,
                (height + (3 - height) * compress) / height, 1))
        }
        addSubmissionAnimations([("transform", transforms),
            ("opacity", times.map { 1 - submissionSmooth(($0 - 0.30) / 0.20) })],
            keyTimes: keyTimes, duration: duration, to: snapshot)

        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let flash = dark ? NSColor(srgbRed: 230/255, green: 1, blue: 244/255, alpha: 1)
            : NSColor(srgbRed: 49/255, green: 95/255, blue: 87/255, alpha: 1)
        let glow = dark ? NSColor(srgbRed: 144/255, green: 230/255, blue: 210/255, alpha: 1)
            : NSColor(srgbRed: 117/255, green: 185/255, blue: 172/255, alpha: 1)
        let line = CAGradientLayer()
        line.name = "ufoLine"
        line.bounds = CGRect(x: 0, y: 0, width: width, height: 3)
        line.position = snapshot.position
        line.colors = [glow.withAlphaComponent(0).cgColor, glow.cgColor, flash.cgColor,
            glow.cgColor, glow.withAlphaComponent(0).cgColor]
        line.locations = [0, 0.1, 0.5, 0.9, 1]
        line.startPoint = CGPoint(x: 0, y: 0.5)
        line.endPoint = CGPoint(x: 1, y: 0.5)
        line.cornerRadius = 1.5
        line.shadowColor = glow.cgColor
        line.shadowRadius = 12
        line.shadowOffset = .zero
        line.shadowOpacity = 1
        container.addSublayer(line)
        let lineBounds = times.map { t -> NSValue in
            let cardWidth = width * (1 + 0.08 * submissionSmooth(t / 0.46))
            let collapse = submissionSmooth((t - 0.46) / 0.30)
            return NSValue(rect: CGRect(x: 0, y: 0, width: cardWidth + (2 - cardWidth) * collapse,
                height: 3 - collapse))
        }
        let lineOpacity = times.map { submissionSmooth(($0 - 0.30) / 0.16) * (1 - submissionSmooth(($0 - 0.82) / 0.18)) }
        addSubmissionAnimations([("bounds", lineBounds), ("opacity", lineOpacity)],
            keyTimes: keyTimes, duration: duration, to: line)

        let star = CAShapeLayer()
        star.name = "ufoTwinkle"
        star.bounds = CGRect(x: -10, y: -10, width: 20, height: 20)
        star.position = snapshot.position
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -10))
        path.addQuadCurve(to: CGPoint(x: 10, y: 0), control: CGPoint(x: 1.2, y: -1.2))
        path.addQuadCurve(to: CGPoint(x: 0, y: 10), control: CGPoint(x: 1.2, y: 1.2))
        path.addQuadCurve(to: CGPoint(x: -10, y: 0), control: CGPoint(x: -1.2, y: 1.2))
        path.addQuadCurve(to: CGPoint(x: 0, y: -10), control: CGPoint(x: -1.2, y: -1.2))
        path.closeSubpath()
        star.path = path
        star.fillColor = flash.cgColor
        star.shadowColor = glow.cgColor
        star.shadowOffset = .zero
        star.shadowOpacity = 1
        container.addSublayer(star)
        let twinkle = times.map { sin(min(1, max(0, ($0 - 0.72) / 0.28)) * .pi) }
        addSubmissionAnimations([("opacity", twinkle), ("transform.scale", twinkle),
            ("shadowRadius", twinkle.map { 14 * $0 })], keyTimes: keyTimes, duration: duration, to: star)
    }

    private func submissionSmooth(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    private func addSubmissionAnimations(_ values: [(String, [Any])], keyTimes: [NSNumber],
                                        duration: TimeInterval, to layer: CALayer) {
        let group = CAAnimationGroup()
        group.animations = values.map { keyPath, values in
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.keyTimes = keyTimes
            animation.duration = duration
            return animation
        }
        group.duration = duration
        group.fillMode = .both
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: "submission")
    }

    /// 焦点落位编辑器，并把编辑器内容重建为当前草稿。
    private func focusTextEditor() {
        guard let textView = focusTarget.textView as? EditorTextView else { return }
        let reason: EditorTextView.ReplacementReason = focusTarget.preserveSelectionOnNextFocus ? .synchronize : .restoreDraft
        guard textView.setPlainText(text.wrappedValue, reason: reason) else { return }
        focusTarget.preserveSelectionOnNextFocus = false
        if !isKeyWindow {
            makeKey()
        }
        makeFirstResponder(textView)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
    }

    /// 面板内快捷键先于编辑器处理；输入法、其他窗口和弹窗保持原生按键行为。
    func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.window === self, isVisible, isKeyWindow,
              attachedSheet == nil, NSApp.modalWindow == nil,
              let textView = focusTarget.textView,
              !textView.hasMarkedText() else { return event }
        _ = textView
        // 历史翻阅（↑/↓）与处理面板（⌘O）已随沉淀层退场；编辑器保留原生按键行为。
        return event
    }
}

/// 只绘制面板内侧的细边；不参与 SwiftUI 更新、鼠标命中或键盘响应。
@MainActor
final class RecordPanelGlowView: NSView {
    private let core = CALayer()
    private let halo = CALayer()
    private let coreMask = CAShapeLayer()
    private let haloMask = CALayer()
    private var fields: [CAGradientLayer] = []
    private var bases: [CAGradientLayer] = []
    private var geometry: CGRect = .zero
    private var motionEpoch: CFTimeInterval?
    private(set) var isActive = false
    private(set) var reduceMotion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = RecordPanel.cornerRadius
        layer?.opacity = 0
        isHidden = true
        setAccessibilityElement(false)
        for (container, mask) in [(halo, haloMask), (core, coreMask)] {
            container.mask = mask
            layer?.addSublayer(container)
            let base = CAGradientLayer()
            base.type = .conic
            base.startPoint = CGPoint(x: 0.5, y: 0.5)
            base.endPoint = CGPoint(x: 0.5, y: 1)
            base.locations = [0, 0.18, 0.38, 0.55, 0.72, 0.88, 1]
            container.addSublayer(base)
            bases.append(base)
            for _ in 0..<2 {
                let field = CAGradientLayer()
                field.type = .radial
                field.startPoint = CGPoint(x: 0.5, y: 0.5)
                field.endPoint = CGPoint(x: 1, y: 1)
                field.locations = [0, 0.35, 1]
                container.addSublayer(field)
                fields.append(field)
            }
        }
        coreMask.fillColor = nil
        coreMask.strokeColor = NSColor.white.cgColor
        coreMask.lineWidth = 0.8
        // B 方案只保留克制的内侧聚焦光：边界可见，但不与正文争抢注意力。
        for (width, opacity): (CGFloat, Float) in [(4, 0.03), (2.5, 0.08), (1.2, 0.18)] {
            let stroke = CAShapeLayer()
            stroke.fillColor = nil
            stroke.strokeColor = NSColor.white.cgColor
            stroke.lineWidth = width
            stroke.opacity = opacity
            haloMask.addSublayer(stroke)
        }
        updateColors()
        needsLayout = true
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard geometry != bounds else { return }
        geometry = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = CGPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75),
            cornerWidth: RecordPanel.cornerRadius - 0.75, cornerHeight: RecordPanel.cornerRadius - 0.75, transform: nil)
        for container in [core, halo, coreMask, haloMask] { container.frame = bounds }
        coreMask.path = path
        for case let stroke as CAShapeLayer in haloMask.sublayers ?? [] {
            stroke.frame = bounds
            stroke.path = path
        }
        for base in bases { base.frame = bounds }
        for (index, field) in fields.enumerated() {
            field.bounds = CGRect(x: 0, y: 0, width: min(460, max(150, perimeter * 0.26)),
                height: min(300, max(120, bounds.height * 1.1)))
            field.position = point(at: index % 2 == 0 ? 0.12 : 0.65)
        }
        updateScale()
        if isActive && !reduceMotion { animateFields() }
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScale()
    }

    private func updateScale() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = window?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        for item in [core, halo, coreMask, haloMask] + bases + fields + (haloMask.sublayers ?? []) {
            item.contentsScale = scale
        }
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private var palette: [NSColor] {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        // 与品牌图标一致的冷蓝色域；浅色外观使用更深的蓝色保持边缘对比。
        let rgb: [(CGFloat, CGFloat, CGFloat)] = dark
            ? [(0.26, 0.54, 1.0), (0.36, 0.77, 1.0), (0.60, 0.86, 1.0), (0.34, 0.49, 0.90)]
            : [(0.12, 0.36, 0.72), (0.12, 0.49, 0.70), (0.25, 0.57, 0.78), (0.22, 0.35, 0.70)]
        return rgb.map { NSColor(srgbRed: $0.0, green: $0.1, blue: $0.2, alpha: 1) }
    }

    private func colors(_ index: Int) -> [CGColor] {
        let colors = palette
        return [colors[index % 4].withAlphaComponent(0.72).cgColor,
                colors[(index + 1) % 4].withAlphaComponent(0.42).cgColor,
                colors[(index + 1) % 4].withAlphaComponent(0).cgColor]
    }

    private func updateColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let colors = palette
        for base in bases {
            base.colors = [0, 1, 2, 3, 2, 1, 0].map { colors[$0].withAlphaComponent(0.10).cgColor }
        }
        for (index, field) in fields.enumerated() { field.colors = self.colors(index % 2 * 2) }
        if isActive && !reduceMotion { animateFields() }
        CATransaction.commit()
    }

    /// 只有真实显示生命周期调用；重复输入、布局和外观变更不会重播入场。
    func start(reduceMotion: Bool) {
        setReducedMotion(reduceMotion)
        guard !isActive else { return }
        isActive = true
        isHidden = false
        layoutSubtreeIfNeeded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let from = layer?.presentation()?.opacity ?? layer?.opacity ?? 0
        layer?.removeAllAnimations()
        halo.removeAllAnimations()
        layer?.opacity = 0.72
        halo.opacity = 0.38
        if !reduceMotion {
            if motionEpoch == nil { motionEpoch = CACurrentMediaTime() }
            animateFields()
            let bloom = CAKeyframeAnimation(keyPath: "opacity")
            bloom.values = [0, 0.68, 0.38]
            bloom.keyTimes = [0, 0.42, 1]
            bloom.duration = 0.42
            halo.add(bloom, forKey: "appearance")
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = 0.72
        fade.duration = reduceMotion ? 0.10 : 0.20
        layer?.add(fade, forKey: "appearance")
        CATransaction.commit()
    }

    /// 收起时只沿用窗口已有的淡出时间；隐藏/失焦/截图前立即清理所有动画。
    func stop(duration: TimeInterval = 0) {
        isActive = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let from = layer?.presentation()?.opacity ?? layer?.opacity ?? 0
        freezeFields()
        layer?.removeAllAnimations()
        halo.removeAllAnimations()
        layer?.opacity = 0
        if duration == 0 { isHidden = true }
        if duration > 0 && from > 0 {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = from
            fade.toValue = 0
            fade.duration = duration
            layer?.add(fade, forKey: "appearance")
            let soften = CABasicAnimation(keyPath: "opacity")
            soften.fromValue = halo.presentation()?.opacity ?? halo.opacity
            soften.toValue = 0
            soften.duration = duration * 0.55
            halo.opacity = 0
            halo.add(soften, forKey: "appearance")
        }
        CATransaction.commit()
    }

    func setReducedMotion(_ reduced: Bool) {
        guard reduceMotion != reduced else { return }
        reduceMotion = reduced
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.removeAllAnimations()
        halo.removeAllAnimations()
        freezeFields()
        if isActive && !reduced { animateFields() }
        CATransaction.commit()
    }

    private func freezeFields() {
        for field in fields {
            if field.animation(forKey: "travel") != nil, let current = field.presentation() {
                field.position = current.position
                if let colors = current.colors { field.colors = colors }
            }
            field.removeAllAnimations()
        }
    }

    private var perimeter: CGFloat {
        2 * (bounds.width + bounds.height - 3 - 4 * (RecordPanel.cornerRadius - 0.75))
            + 2 * .pi * (RecordPanel.cornerRadius - 0.75)
    }

    /// 与预览相同的周长坐标；亮区贴着实际圆角走，不旋转整圈渐变。
    private func point(at phase: CGFloat) -> CGPoint {
        let w = bounds.width - 1.5, h = bounds.height - 1.5, r = RecordPanel.cornerRadius - 0.75
        let lengths = [w - 2 * r, .pi * r / 2, h - 2 * r, .pi * r / 2,
                       w - 2 * r, .pi * r / 2, h - 2 * r, .pi * r / 2]
        var distance = (phase - floor(phase)) * perimeter, side = 0
        while side < 7 && distance > lengths[side] { distance -= lengths[side]; side += 1 }
        let point: CGPoint
        switch side {
        case 0: point = CGPoint(x: r + distance, y: 0)
        case 2: point = CGPoint(x: w, y: r + distance)
        case 4: point = CGPoint(x: w - r - distance, y: h)
        case 6: point = CGPoint(x: 0, y: h - r - distance)
        default:
            let corner = (side - 1) / 2
            let centers = [CGPoint(x: w - r, y: r), CGPoint(x: w - r, y: h - r),
                           CGPoint(x: r, y: h - r), CGPoint(x: r, y: r)]
            let angle = (-0.5 + CGFloat(corner) * 0.5 + distance / lengths[side] * 0.5) * .pi
            point = CGPoint(x: centers[corner].x + cos(angle) * r, y: centers[corner].y + sin(angle) * r)
        }
        return CGPoint(x: bounds.minX + 0.75 + point.x, y: bounds.maxY - 0.75 - point.y)
    }

    private func animateFields() {
        guard isActive, !reduceMotion, !bounds.isEmpty else { return }
        if motionEpoch == nil { motionEpoch = CACurrentMediaTime() }
        for (index, field) in fields.enumerated() {
            let secondary = index % 2 == 1
            let movement = CAKeyframeAnimation(keyPath: "position")
            movement.values = (0...256).map { step in
                let time = CGFloat(step) / 256
                return NSValue(point: point(at: (secondary ? 0.65 : 0.12) + time + sin(time * 2 * .pi) * 0.017))
            }
            movement.duration = secondary ? 9.45 : 6.9
            movement.repeatCount = .infinity
            movement.beginTime = field.convertTime(motionEpoch!, from: nil)
            field.add(movement, forKey: "travel")
            let color = CAKeyframeAnimation(keyPath: "colors")
            let offset = secondary ? 2 : 0
            color.values = (0...4).map { colors(($0 + offset) % 4) }
            color.duration = secondary ? 13.7 : 10.2
            color.repeatCount = .infinity
            color.beginTime = movement.beginTime
            field.add(color, forKey: "color")
        }
    }
}
