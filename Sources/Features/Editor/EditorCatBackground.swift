import AppKit
import SwiftUI

struct EditorCatBackground: NSViewRepresentable {
    let focusTarget: EditorFocusTarget
    let enabled: Bool
    let isReading: Bool
    let colorScheme: ColorScheme
    let controlRects: [CGRect]
    let targetRect: CGRect?
    let hasDraftContent: Bool

    func makeNSView(context: Context) -> EditorCatView {
        let view = EditorCatView()
        view.focusTarget = focusTarget
        focusTarget.decorationBackground = view
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: EditorCatView, context: Context) {
        view.configure(enabled: enabled, isReading: isReading, isDark: colorScheme == .dark,
                       controlRects: controlRects, targetRect: targetRect, hasDraftContent: hasDraftContent)
    }

    static func dismantleNSView(_ view: EditorCatView, coordinator: ()) {
        view.suspend()
        if view.focusTarget?.decorationBackground === view {
            view.focusTarget?.decorationBackground = nil
        }
    }
}

/// A decorative view only: no draft content, event interception, or per-frame SwiftUI updates.
@MainActor
final class EditorCatView: NSView, EditorDecorationView {
    weak var focusTarget: EditorFocusTarget?
    private var enabled = false
    private var isReading = false
    private var isDark = false
    private var panelSuspended = false
    private var sleeping = false
    private var selecting = false
    private var restTimer: Timer?
    private var animationTimer: Timer?
    private var returnExpressionTimer: Timer?
    private var returnExpression: ASCIICat.Expression?
    private var mouseMonitor: Any?
    private var clickOrigin: CGPoint?
    private var gaze: CGPoint?
    private var gestureStartedAt: TimeInterval?
    private var gestureProgress: CGFloat = 0
    private var motion = CatPerchMotion()
    private var arrival = CatPerchMotion.Arrival.peek
    private var targetRect: CGRect?
    // Keep the perch relative to the floor, independently of the button's
    // lifetime. The head returns to the same grounded body, not a second cat.
    private var perchBottomInset: CGFloat?
    private var retainedTargetRect: CGRect?
    private var controlReleasedAt: TimeInterval?
    private var hasDraftContent = false
    private var lastActivity: TimeInterval = 0
    private var geometryDirty = true
    private var protectedRects: [CGRect] = []
    private var controlRects: [CGRect] = []
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var editor: EditorTextView? { focusTarget?.textView as? EditorTextView }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowChanged(_:)), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled(_:)),
                                               name: NSView.boundsDidChangeNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(preferencesChanged),
                              name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    isolated deinit {
        restTimer?.invalidate()
        animationTimer?.invalidate()
        returnExpressionTimer?.invalidate()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func configure(enabled: Bool, isReading: Bool, isDark: Bool, controlRects: [CGRect],
                   targetRect: CGRect?, hasDraftContent: Bool) {
        let readingChanged = self.isReading != isReading
        let draftChanged = self.hasDraftContent != hasDraftContent
        self.enabled = enabled
        self.isReading = isReading
        self.isDark = isDark
        self.hasDraftContent = hasDraftContent
        let measuredTarget = targetRect.flatMap { $0.isEmpty || $0.isInfinite ? nil : $0 }
        if measuredTarget != self.targetRect || perchBottomInset == nil {
            rememberPerch(measuredTarget)
        }
        if measuredTarget != nil {
            controlReleasedAt = nil
        } else if self.targetRect != nil {
            controlReleasedAt = now
        }
        self.targetRect = measuredTarget
        let measuredControls = controlRects.filter { !$0.isEmpty && !$0.isInfinite }
        if self.controlRects != measuredControls {
            self.controlRects = measuredControls
            invalidateGeometry()
        }
        if draftChanged {
            clearReturnExpression()
            if !hasDraftContent, canAnimate, pose.reveal > 0 || motion.isMoving(at: now) {
                returnExpression = .curious
            }
            if hasDraftContent, pose.reveal == 0, !motion.isMoving(at: now) {
                // An interrupted return keeps its current arrival and silhouette.
                arrival = Int.random(in: 0..<5) == 0 ? .hop : .peek
            }
            gestureStartedAt = nil
            gestureProgress = 0
            restTimer?.invalidate()
            restTimer = nil
            setGaze(nil)
        }
        updateDestination()
        if readingChanged { noteActivity() }
        refreshSchedule()
        needsDisplay = true
    }

    func invalidateGeometry() {
        geometryDirty = true
        needsDisplay = true
    }

    func noteActivity() {
        lastActivity = now
        invalidateGeometry()
        // Only an empty/nonempty transition changes the perch. Ordinary typing
        // postpones the next play gesture without replaying the current motion.
        restTimer?.invalidate()
        restTimer = nil
        refreshSchedule()
    }

    func setSelecting(_ selecting: Bool) {
        self.selecting = selecting
        noteActivity()
    }

    /// Called before all panel hide paths, including ones that bypass orderOut's override.
    func suspend() {
        panelSuspended = true
        refreshSchedule()
    }

    func resume() {
        panelSuspended = false
        invalidateGeometry()
        refreshSchedule()
    }

    private var canAnimate: Bool {
        enabled && !panelSuspended && !sleeping && !isHiddenOrHasHiddenAncestor
            && window?.isVisible == true && window?.isKeyWindow == true
            && window?.occlusionState.contains(.visible) == true
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            && bounds.width >= 160 && bounds.height >= 100
    }

    private var isEditing: Bool {
        selecting || isReading || editor?.hasMarkedText() == true
    }

    private var uncoveredOpacity: CGFloat {
        guard targetRect == nil else { return 0 }
        guard let controlReleasedAt else { return 1 }
        let t = min(1, max(0, CGFloat((now - controlReleasedAt) / 0.28)))
        return t * t * (3 - 2 * t)
    }

    private var isTransitioning: Bool {
        motion.isMoving(at: now) || (targetRect == nil && uncoveredOpacity < 1)
    }

    private func refreshSchedule() {
        guard canAnimate else {
            stop()
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
            mouseMonitor = nil
            clickOrigin = nil
            setGaze(nil)
            return
        }
        installMouseMonitor()
        if isEditing {
            // Pause play, not an already requested transition. Settling here
            // would make IME or selection jump the cat straight to its endpoint.
            gestureStartedAt = nil
            gestureProgress = 0
            setGaze(nil)
        }
        if isTransitioning || gestureStartedAt != nil {
            startAnimationTimer()
            return
        }
        animationTimer?.invalidate()
        animationTimer = nil
        scheduleSmileReturn()
        // No frame timer while resting, and no automatic play while perched.
        guard !isEditing, !hasDraftContent, restTimer == nil else { return }
        let delay = max(Double.random(in: 8...14), lastActivity + 6 - now)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.restTimer = nil
                self.startGesture()
            }
        }
        timer.tolerance = 0.5
        restTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleSmileReturn() {
        guard let returnExpression, returnExpressionTimer == nil else { return }
        // Hold round eyes after landing, then close them briefly before smiling.
        // Each phase needs only one wake-up, with no frame ticks while resting.
        let duration: TimeInterval = returnExpression == .blink ? 0.15 : 2
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.returnExpressionTimer = nil
                if self.returnExpression == .curious {
                    self.returnExpression = .blink
                    self.scheduleSmileReturn()
                } else {
                    self.clearReturnExpression()
                }
                self.needsDisplay = true
            }
        }
        timer.tolerance = 0.01
        returnExpressionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func clearReturnExpression() {
        returnExpressionTimer?.invalidate()
        returnExpressionTimer = nil
        returnExpression = nil
    }

    private func startGesture(fromClick: Bool = false) {
        guard canAnimate, !isEditing else { refreshSchedule(); return }
        guard gestureStartedAt == nil, !isTransitioning else { return }
        refreshProtectedRects()
        guard (fromClick || now - lastActivity >= 6), hasRoomForCat else { refreshSchedule(); return }
        restTimer?.invalidate()
        restTimer = nil
        gestureStartedAt = now
        startAnimationTimer()
    }

    private func startAnimationTimer() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.005
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        guard canAnimate else { stop(); return }
        if isEditing {
            gestureStartedAt = nil
            gestureProgress = 0
        }
        if let started = gestureStartedAt {
            gestureProgress = min(1, CGFloat((now - started) / ASCIICat.gestureDuration))
            if gestureProgress >= 1 {
                gestureStartedAt = nil
                gestureProgress = 0
            }
        }
        needsDisplay = true
        if !isTransitioning, gestureStartedAt == nil {
            animationTimer?.invalidate()
            animationTimer = nil
            refreshSchedule()
        }
    }

    private func stop() {
        restTimer?.invalidate()
        restTimer = nil
        animationTimer?.invalidate()
        animationTimer = nil
        gestureStartedAt = nil
        gestureProgress = 0
        controlReleasedAt = nil
        clearReturnExpression()
        motion.settle()
        needsDisplay = true
    }

    private var groundAnchor: CGPoint {
        CGPoint(x: bounds.maxX - 68, y: bounds.maxY - 16)
    }

    private var pose: CatPerchMotion.Pose {
        motion.pose(at: now)
    }

    private func rememberPerch(_ rect: CGRect?) {
        guard let rect, bounds.height >= 100, rect.minY > 0,
              rect.maxY <= bounds.maxY + 1 else { return }
        perchBottomInset = bounds.maxY - rect.minY + 4
        retainedTargetRect = rect
    }

    private func updateDestination() {
        guard bounds.width >= 160, bounds.height >= 100 else { return }
        if perchBottomInset == nil { rememberPerch(targetRect) }
        motion.setPerched(hasDraftContent && perchBottomInset != nil, arrival: arrival,
                          at: now, animated: canAnimate)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDestination()
        invalidateGeometry()
        refreshSchedule()
    }

    override func viewDidHide() { super.viewDidHide(); refreshSchedule() }
    override func viewDidUnhide() { super.viewDidUnhide(); refreshSchedule() }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = frame.size != newSize
        super.setFrameSize(newSize)
        if changed {
            updateDestination()
            invalidateGeometry()
            refreshSchedule()
        }
    }

    @objc private func windowChanged(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        if notification.name == NSWindow.didBecomeKeyNotification { panelSuspended = false }
        invalidateGeometry()
        refreshSchedule()
    }

    @objc private func scrolled(_ notification: Notification) {
        guard notification.object as? NSClipView === editor?.enclosingScrollView?.contentView else { return }
        noteActivity()
    }

    @objc private func preferencesChanged() {
        invalidateGeometry()
        refreshSchedule()
    }
    @objc private func willSleep() { sleeping = true; refreshSchedule() }
    @objc private func didWake() { sleeping = false; refreshSchedule() }

    private var catFrame: CGRect {
        var rect = headFrame
        if pose.bodyOpacity > 0.01 { rect = rect.union(bodyFrame) }
        if pawOpacity > 0.01 { rect = rect.union(pawFrame) }
        return rect
    }

    private var bodyFrame: CGRect {
        ASCIICat.bounds(anchor: groundAnchor, layer: .body)
    }

    private var perchEdge: CGFloat {
        bounds.maxY - (perchBottomInset ?? 42)
    }

    private var headAnchor: CGPoint {
        let rise = pose.headRise
        let height: CGFloat = arrival == .peek ? 21 : 36
        let perchedY = perchEdge + 31 - height
        let lift = arrival == .hop ? 8 * sin(rise * .pi) : 0
        return CGPoint(x: groundAnchor.x,
                       y: groundAnchor.y + (perchedY - groundAnchor.y) * rise - lift)
    }

    private var revealEdge: CGFloat {
        // Release the decorative mask along with the posture. Keeping it at
        // the vanished button would swallow the face before it reached home.
        bounds.maxY + (perchEdge - bounds.maxY) * pose.headRise
    }

    private var revealArea: CGRect {
        CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
               height: max(0, revealEdge - bounds.minY))
    }

    private var headFrame: CGRect {
        ASCIICat.bounds(anchor: headAnchor, layer: .head).intersection(revealArea)
    }

    private var pawAnchor: CGPoint {
        arrival == .hop ? headAnchor : groundAnchor
    }

    private var pawOpacity: CGFloat {
        arrival == .hop ? 1 : pose.bodyOpacity
    }

    private var pawFrame: CGRect {
        let rect = ASCIICat.bounds(anchor: pawAnchor, layer: .paws)
        return arrival == .hop ? rect.intersection(revealArea) : rect
    }

    private func hasRoom(for rect: CGRect, behindPerch: Bool = false) -> Bool {
        let perch = behindPerch ? targetRect?.insetBy(dx: -4, dy: -4) : nil
        return !rect.isEmpty && bounds.insetBy(dx: 4, dy: 4).contains(rect)
            && !protectedRects.contains { $0 != perch && $0.intersects(rect) }
    }

    private var hasRoomForCat: Bool {
        hasRoom(for: catFrame, behindPerch: pose.reveal > 0)
    }

    func trackPointer(_ location: CGPoint?) {
        refreshProtectedRects()
        guard canAnimate, !isEditing, !isTransitioning, hasRoomForCat, let location,
              catFrame.insetBy(dx: -12, dy: -12).contains(location) else { setGaze(nil); return }
        setGaze(CGPoint(x: max(-1, min(1, (location.x - catFrame.midX) / (catFrame.width / 2))),
                       y: max(-1, min(1, (location.y - catFrame.midY) / (catFrame.height / 2)))))
    }

    private func setGaze(_ value: CGPoint?) {
        guard gaze != value else { return }
        gaze = value
        setNeedsDisplay(catFrame)
    }

    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        // Observe only this window's ordinary clicks. Never consume or replace
        // an event: text selection, caret positioning, controls and dragging stay native.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self, event.window === self.window, self.canAnimate else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            if event.type == .leftMouseDown {
                self.refreshProtectedRects()
                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                self.clickOrigin = modifiers.isEmpty && !self.isEditing && self.hasRoomForCat
                    && self.catFrame.contains(point) ? point : nil
            } else if let start = self.clickOrigin {
                self.clickOrigin = nil
                guard hypot(start.x - point.x, start.y - point.y) < 4,
                      self.catFrame.contains(point) else { return event }
                // Let NSTextView finish its native mouse-selection loop first.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.canAnimate, !self.isEditing else { return }
                    self.invalidateGeometry()
                    self.trackPointer(point)
                    self.startGesture(fromClick: true)
                }
            }
            return event
        }
    }

    private func refreshProtectedRects() {
        guard geometryDirty else { return }
        geometryDirty = false
        protectedRects = controlRects.map { $0.insetBy(dx: -4, dy: -4) }
        guard let editor, editor.window === window, let scroll = editor.enclosingScrollView else {
            protectedRects = [bounds]
            return
        }
        let visible = editor.visibleRect
        let viewport = convert(scroll.contentView.bounds, from: scroll.contentView)
        // Marked text (including its selected segment) is covered by the native
        // line and caret geometry below. Keep unused space visible during IME.
        // Ordinary selections still conservatively protect the whole viewport.
        if !editor.hasMarkedText(), editor.selectedRanges.contains(where: { $0.rangeValue.length > 0 }) {
            protectedRects.append(viewport.insetBy(dx: -6, dy: -6))
            return
        }
        if editor.string.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: editor.font ?? NSFont.systemFont(ofSize: LauncherMetrics.editorFontSize),
                .paragraphStyle: editor.defaultParagraphStyle ?? NSParagraphStyle.default,
            ]
            var rect = (editor.placeholder as NSString).boundingRect(
                with: CGSize(width: viewport.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
            rect.origin = editor.textContainerOrigin
            protectedRects.append(convert(rect, from: editor).insetBy(dx: -6, dy: -6))
        } else if let manager = editor.textLayoutManager {
            let origin = editor.textContainerOrigin
            let start = manager.textViewportLayoutController.viewportRange?.location ?? manager.documentRange.location
            var found = false
            manager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
                let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
                if frame.minY > visible.maxY { return false }
                for line in fragment.textLineFragments {
                    let rect = line.typographicBounds.offsetBy(dx: frame.minX, dy: frame.minY)
                    guard rect.intersects(visible) else { continue }
                    found = true
                    self.protectedRects.append(self.convert(rect, from: editor).insetBy(dx: -6, dy: -6))
                }
                return true
            }
            if !found { protectedRects.append(viewport.insetBy(dx: -6, dy: -6)) }
        } else {
            protectedRects.append(viewport.insetBy(dx: -6, dy: -6))
        }
        let selection = editor.selectedRange()
        guard selection.location != NSNotFound else {
            protectedRects.append(viewport.insetBy(dx: -6, dy: -6))
            return
        }
        let caret = editor.firstRect(forCharacterRange: NSRange(location: selection.location, length: 0), actualRange: nil)
        if let window, caret.height > 0, !caret.isInfinite, !caret.isNull {
            // An insertion range can have zero width, but its caret still needs a clear region.
            let caretArea = CGRect(x: caret.minX, y: caret.minY, width: max(2, caret.width), height: caret.height)
            protectedRects.append(convert(window.convertFromScreen(caretArea), from: nil).insetBy(dx: -6, dy: -6))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard enabled, !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
              let context = NSGraphicsContext.current?.cgContext else { return }
        refreshProtectedRects()
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(roundedRect: bounds, xRadius: LauncherMetrics.inputCardCornerRadius,
                     yRadius: LauncherMetrics.inputCardCornerRadius).addClip()
        // The real button disappears immediately. Release only its old cat
        // cutout over 280 ms, including when deletion interrupts an arrival.
        // Pixels already above the button stay fully visible throughout.
        if var cutout = targetRect ?? retainedTargetRect, uncoveredOpacity < 1 {
            if targetRect == nil { cutout.origin.y = perchEdge + 4 }
            cutout = cutout.insetBy(dx: -4, dy: -4)
            context.saveGState()
            let clip = CGMutablePath()
            clip.addRect(bounds)
            clip.addRect(cutout)
            context.addPath(clip)
            context.clip(using: .evenOdd)
            drawCat(in: context)
            context.restoreGState()
            if uncoveredOpacity > 0 {
                context.saveGState()
                context.clip(to: cutout)
                context.setAlpha(uncoveredOpacity)
                drawCat(in: context)
                context.restoreGState()
            }
        } else {
            drawCat(in: context)
        }
    }

    private func drawCat(in context: CGContext) {
        let pose = pose
        let canDrawHead = hasRoom(for: headFrame, behindPerch: true)
        // If text hides the face, hide its body too rather than leave headless
        // fragments below the protected text. A clear head may still peek out.
        if canDrawHead, hasRoom(for: bodyFrame, behindPerch: motion.isMoving(at: now)) {
            ASCIICat.draw(in: context, anchor: groundAnchor, layer: .body, peek: 0,
                          gestureProgress: gestureProgress, gaze: gaze,
                          isHopping: false, isDark: isDark, restingFold: pose.restingFold,
                          opacity: pose.bodyOpacity)
        }
        if canDrawHead, hasRoom(for: pawFrame, behindPerch: true) {
            context.saveGState()
            if arrival == .hop { context.clip(to: revealArea) }
            ASCIICat.draw(in: context, anchor: pawAnchor, layer: .paws, peek: pose.headRise,
                          gestureProgress: gestureProgress, isHopping: false, isDark: isDark,
                          opacity: pawOpacity)
            context.restoreGState()
        }
        // Draw exactly one face throughout entry, return and reversals.
        context.saveGState()
        context.clip(to: revealArea)
        if canDrawHead {
            ASCIICat.draw(in: context, anchor: headAnchor, layer: .head, peek: pose.headRise,
                          gestureProgress: gestureProgress, gaze: gaze,
                          isHopping: arrival == .hop && pose.velocity > 0
                              && pose.reveal > 0.02 && pose.reveal < 0.98,
                          isDark: isDark, restingFold: pose.restingFold,
                          expressionOverride: returnExpression)
        }
        context.restoreGState()
        if hasRoom(for: ASCIICat.ballBounds(anchor: groundAnchor)) {
            ASCIICat.drawBall(in: context, anchor: groundAnchor, gestureProgress: gestureProgress,
                              opacity: pose.bodyOpacity * pose.bodyOpacity, isDark: isDark)
        }
    }
}
