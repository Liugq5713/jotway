import AppKit
import SwiftUI

struct EditorSharkBackground: NSViewRepresentable {
    let focusTarget: EditorFocusTarget
    let enabled: Bool
    let isReading: Bool
    let colorScheme: ColorScheme
    let controlRects: [CGRect]

    func makeNSView(context: Context) -> EditorSharkView {
        let view = EditorSharkView()
        view.focusTarget = focusTarget
        focusTarget.decorationBackground = view
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: EditorSharkView, context: Context) {
        view.configure(enabled: enabled, isReading: isReading, isDark: colorScheme == .dark,
                       controlRects: controlRects)
    }

    static func dismantleNSView(_ view: EditorSharkView, coordinator: ()) {
        view.suspend()
        if view.focusTarget?.decorationBackground === view {
            view.focusTarget?.decorationBackground = nil
        }
    }
}

/// A decorative view only: no draft state, event interception, or per-frame SwiftUI updates.
@MainActor
final class EditorSharkView: NSView, EditorDecorationView {
    weak var focusTarget: EditorFocusTarget?
    private var enabled = false
    private var isReading = false
    private var isDark = false
    private var panelSuspended = false
    private var sleeping = false
    private var selecting = false
    private var timer: Timer?
    private var lastFrame: TimeInterval = 0
    private var lastActivity: TimeInterval = 0
    private var motion = SharkSwimMotion()
    private var shark = ASCIIShark()
    private var patrolLane: CGRect?
    private var cruisingTime: TimeInterval = 0
    private var patrolSection = 0
    private var position: CGPoint? { motion.position }
    private var atEdge = false
    private var retreatStartedAt: TimeInterval?
    private var rightEdge = true
    private var opacity: CGFloat = 0
    private var geometryDirty = true
    private var protectedRects: [CGRect] = []
    private var controlRects: [CGRect] = []
    private static let size = ASCIIShark.size
    private static let idleDelay: TimeInterval = 6
    private static let retreatDelay: TimeInterval = 1.2
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
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func configure(enabled: Bool, isReading: Bool, isDark: Bool, controlRects: [CGRect]) {
        let readingChanged = self.isReading != isReading
        self.enabled = enabled
        self.isReading = isReading
        self.isDark = isDark
        let measuredControls = controlRects.filter { !$0.isEmpty && !$0.isInfinite }
        if self.controlRects != measuredControls {
            self.controlRects = measuredControls
            invalidateGeometry()
        }
        if readingChanged { noteActivity() }
        refreshSchedule()
        needsDisplay = true
    }

    func invalidateGeometry() {
        geometryDirty = true
        patrolLane = nil
        needsDisplay = true
    }

    func noteActivity() {
        lastActivity = now
        invalidateGeometry()
        guard timer != nil, !atEdge, let position else { return }
        atEdge = true
        retreatStartedAt = now
        rightEdge = position.x >= bounds.midX
    }

    func setSelecting(_ selecting: Bool) {
        self.selecting = selecting
        noteActivity()
    }

    /// Called before all panel hide paths, including ones that bypass orderOut's override.
    func suspend() {
        panelSuspended = true
        stop()
    }

    func resume() {
        panelSuspended = false
        refreshSchedule()
    }

    private var canAnimate: Bool {
        enabled && !panelSuspended && !sleeping && !isHiddenOrHasHiddenAncestor
            && window?.isVisible == true && window?.isKeyWindow == true
            && window?.occlusionState.contains(.visible) == true
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            && bounds.width > Self.size.width && swimmingBounds.height >= Self.size.height
    }

    private func refreshSchedule() {
        guard canAnimate else { stop(); return }
        guard timer == nil else { return }
        invalidateGeometry()
        refreshProtectedRects()
        let time = now
        lastFrame = time
        lastActivity = editor?.string.isEmpty == true && !isReading ? time - Self.idleDelay : time
        motion.resume()
        atEdge = false
        retreatStartedAt = nil
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.002
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        opacity = 0
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        invalidateGeometry()
        refreshSchedule()
    }

    override func viewDidHide() { super.viewDidHide(); stop() }
    override func viewDidUnhide() { super.viewDidUnhide(); refreshSchedule() }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = frame.size != newSize
        super.setFrameSize(newSize)
        if changed {
            invalidateGeometry()
            refreshSchedule()
        }
    }

    @objc private func windowChanged(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        if notification.name == NSWindow.didBecomeKeyNotification { panelSuspended = false }
        refreshSchedule()
    }

    @objc private func scrolled(_ notification: Notification) {
        guard notification.object as? NSClipView === editor?.enclosingScrollView?.contentView else { return }
        noteActivity()
    }

    @objc private func preferencesChanged() { refreshSchedule() }
    @objc private func willSleep() { sleeping = true; stop() }
    @objc private func didWake() { sleeping = false; refreshSchedule() }

    private var swimmingBounds: CGRect {
        CGRect(x: 4, y: 4, width: max(0, bounds.width - 8), height: max(0, bounds.height - 8))
    }

    private var edgePosition: CGPoint {
        CGPoint(x: rightEdge ? bounds.maxX - 10 : bounds.minX + 10,
                y: min(max(position?.y ?? swimmingBounds.midY, swimmingBounds.minY + Self.size.height / 2),
                       swimmingBounds.maxY - Self.size.height / 2))
    }

    private func tick() {
        guard canAnimate else { stop(); return }
        let time = now
        let delta = min(max(time - lastFrame, 0), 0.1)
        lastFrame = time
        if selecting || isReading || editor?.hasMarkedText() == true { lastActivity = time }
        refreshProtectedRects()

        if time - lastActivity < Self.idleDelay {
            if !atEdge {
                atEdge = true
                retreatStartedAt = time
                rightEdge = (position?.x ?? bounds.midX) >= bounds.midX
            }
        } else {
            atEdge = false
            retreatStartedAt = nil
            cruisingTime += delta
            let section = Int(cruisingTime / 9) % 3
            if section != patrolSection {
                patrolSection = section
                patrolLane = nil
            }
        }

        if patrolLane == nil { patrolLane = safePatrolLane() }
        let retreating = atEdge && time - (retreatStartedAt ?? time) >= Self.retreatDelay
        let point = motion.advance(delta: delta, lane: patrolLane ?? .zero,
                                   edge: edgePosition, retreating: retreating)
        shark.advance(to: point, delta: delta)
        let targetOpacity: CGFloat = retreating ? 0.16 : 0.38
        opacity += (targetOpacity - opacity) * min(1, delta * 1.5)
        needsDisplay = true
    }

    private func safePatrolLane() -> CGRect {
        let area = swimmingBounds.insetBy(dx: Self.size.width / 2, dy: Self.size.height / 2)
        var best = CGRect(origin: edgePosition, size: .zero)
        var bestScore: CGFloat = -.greatestFiniteMagnitude
        guard area.width > 0, area.height > 0 else { return best }
        let step = area.width / 24
        let desiredY = area.minY + area.height * [0.85, 0.2, 0.55][patrolSection]
        // Find an open two-dimensional region across the whole card, including the
        // gaps between footer controls. Do not reserve an invisible horizontal strip.
        for top in 0...6 {
            for bottom in top...6 {
                let minY = area.minY + area.height * CGFloat(top) / 6
                let maxY = area.minY + area.height * CGFloat(bottom) / 6
                var start: CGFloat?
                for column in 0...25 {
                    let x = area.minX + step * CGFloat(column)
                    let columnRect = sharkRect(at: CGPoint(x: x, y: minY))
                        .union(sharkRect(at: CGPoint(x: x, y: maxY))).insetBy(dx: -3, dy: -3)
                    let clear = column <= 24 && !protectedRects.contains(where: { $0.intersects(columnRect) })
                    if clear && start == nil { start = x }
                    if !clear, let left = start {
                        let width = max(0, x - step - left)
                        let height = maxY - minY
                        let score = max(12, width) * max(12, height)
                            / (1 + abs((minY + maxY) / 2 - desiredY) / 18)
                        if score > bestScore {
                            bestScore = score
                            best = CGRect(x: left, y: minY, width: width, height: height)
                        }
                        start = nil
                    }
                }
            }
        }
        return best
    }

    private func sharkRect(at point: CGPoint) -> CGRect {
        CGRect(x: point.x - Self.size.width / 2, y: point.y - Self.size.height / 2,
               width: Self.size.width, height: Self.size.height)
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
        // Selection highlights and IME candidates take priority over decoration.
        if editor.hasMarkedText() || editor.selectedRanges.contains(where: { $0.rangeValue.length > 0 }) {
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
        // Intersect successive complements. Overlapping protected rectangles cannot cancel each other out.
        for rect in protectedRects {
            let hole = rect.intersection(bounds)
            guard !hole.isNull else { continue }
            context.clip(to: [
                CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: hole.minY - bounds.minY),
                CGRect(x: bounds.minX, y: hole.maxY, width: bounds.width, height: bounds.maxY - hole.maxY),
                CGRect(x: bounds.minX, y: hole.minY, width: hole.minX - bounds.minX, height: hole.height),
                CGRect(x: hole.maxX, y: hole.minY, width: bounds.maxX - hole.maxX, height: hole.height),
            ])
        }
        guard timer != nil, opacity > 0.01 else { return }
        let color = isDark ? NSColor(calibratedRed: 0.61, green: 0.71, blue: 0.76, alpha: opacity)
            : NSColor(calibratedRed: 0.28, green: 0.37, blue: 0.41, alpha: opacity)
        shark.draw(color: color, in: context)
    }
}
