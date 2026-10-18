import AppKit
import SwiftUI

/// One native entry; its absence removes both layout and accessibility space.
struct RecentDocumentControls: NSViewRepresentable {
    let focusTarget: EditorFocusTarget
    let state: LauncherViewState
    let isCardHovered: Bool
    let increasesContrast: Bool
    let send: (LauncherEvent) -> Void

    func makeNSView(context: Context) -> RecentDocumentButton { RecentDocumentButton() }

    static func dismantleNSView(_ button: RecentDocumentButton, coordinator: ()) {
        guard let target = button.focusTarget else { return }
        if button.window?.firstResponder === button { target.restoreEditorIfRecentDocumentFocused() }
        target.recentDocumentButtons.removeAll { $0 === button }
    }

    func updateNSView(_ button: RecentDocumentButton, context: Context) {
        button.focusTarget = focusTarget
        button.launcherState = state
        focusTarget.recentDocumentButtons = [button]
        button.composing = state.isComposingText
        button.isCardHovered = isCardHovered
        button.increasesContrast = increasesContrast
        button.isSelectedDocument = state.selectedRecentDocumentID != nil
        button.send = send
        button.isEnabled = state.canShowRecentDocuments && state.modeSwitchBlockReason == nil
        button.setAccessibilityElement(state.canShowRecentDocuments)
        button.setAccessibilityLabel(L10n.text("recent_documents.title"))
        button.setAccessibilityHelp(L10n.text("recent_documents.toggle_help"))
        button.setAccessibilityIdentifier("launcher-recent-documents")
        button.toolTip = L10n.text("recent_documents.toggle_help")
        button.refreshAppearance()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RecentDocumentButton, context: Context) -> CGSize? {
        CGSize(width: 22, height: 22)
    }
}

@MainActor
final class RecentDocumentButton: NSButton {
    weak var focusTarget: EditorFocusTarget?
    var launcherState: LauncherViewState?
    var composing = false
    var isCardHovered = false {
        didSet { if isCardHovered != oldValue { refreshHoverFromMouseLocation() } }
    }
    var increasesContrast = false
    var isSelectedDocument = false
    var send: (LauncherEvent) -> Void = { _ in }
    private var keyboardFocused = false
    private var hovered = false
    private var drawingOpacity: CGFloat = 0
    private var emphasis: CGFloat = 0
    private var targetOpacity: CGFloat = 0
    private var targetEmphasis: CGFloat = 0
    private var appearanceTask: Task<Void, Never>?

    override init(frame: NSRect) {
        super.init(frame: frame)
        title = ""; isBordered = false; focusRingType = .none
        target = self; action = #selector(toggleDocuments)
    }

    required init?(coder: NSCoder) { nil }
    isolated deinit { appearanceTask?.cancel() }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var canInteract: Bool {
        isEnabled && !composing && focusTarget?.textView?.hasMarkedText() != true
    }

    override func mouseDown(with event: NSEvent) {
        guard canInteract, isCardHovered || hovered else { return }
        toggleDocuments()
    }

    @objc private func toggleDocuments() {
        guard canInteract else { return }
        send(.toggleRecentDocuments)
    }

    override func keyDown(with event: NSEvent) {
        guard !composing, focusTarget?.textView?.hasMarkedText() != true else { return }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 0x30, modifiers.isEmpty || modifiers == .shift {
            guard !event.isARepeat, let focusTarget else { return }
            if modifiers == .shift { focusTarget.focusModeControl() }
            else if let state = launcherState, state.selectedRecentDocument != nil {
                focusTarget.moveRecentDocumentCommandFocus(from: -1, forward: true, state: state)
            } else { focusTarget.focusFollowingRecentDocument() }
            return
        }
        if event.keyCode == 0x35, modifiers.isEmpty {
            if !event.isARepeat { send(.cancel) }
            return
        }
        guard canInteract else { return }
        if modifiers.isEmpty, [UInt16(0x24), 0x4C, 0x31].contains(event.keyCode) {
            if !event.isARepeat { toggleDocuments() }
            return
        }
        super.keyDown(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil))
        refreshHoverFromMouseLocation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyboardFocused = window?.firstResponder === self
        refreshHoverFromMouseLocation()
    }

    private func refreshHoverFromMouseLocation() {
        // Keep local emphasis in sync when a mode change rebuilds the tracking area.
        if let window, window.isVisible, !isHiddenOrHasHiddenAncestor {
            hovered = visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        } else {
            hovered = false
        }
        refreshAppearance()
    }

    override func cursorUpdate(with event: NSEvent) {
        (canInteract && launcherState?.canShowRecentDocuments == true && (isCardHovered || hovered) ? NSCursor.pointingHand : .arrow).set()
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; refreshAppearance() }
    override func mouseExited(with event: NSEvent) { hovered = false; refreshAppearance() }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { keyboardFocused = true; refreshAppearance() }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { keyboardFocused = false; refreshAppearance() }
        return accepted
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled, !isHidden, drawingOpacity > 0, isCardHovered || hovered {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    fileprivate func refreshAppearance() {
        if launcherState?.canShowRecentDocuments != true { hovered = false }
        let opacity: CGFloat = launcherState?.canShowRecentDocuments == true && (isCardHovered || hovered || keyboardFocused) ? 1 : 0
        let emphasized: CGFloat = isEnabled && (hovered || keyboardFocused) ? 1 : 0
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        guard opacity != targetOpacity || emphasized != targetEmphasis else { return }
        targetOpacity = opacity
        targetEmphasis = emphasized
        appearanceTask?.cancel()
        appearanceTask = nil
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            drawingOpacity = opacity
            emphasis = emphasized
            return
        }
        let initialOpacity = drawingOpacity
        let initialEmphasis = emphasis
        if opacity == 1 { drawingOpacity = 1 }
        appearanceTask = Task { [weak self] in
            for step in 1...8 {
                do { try await Task.sleep(for: .milliseconds(15)) } catch { return }
                guard let self else { return }
                let progress = CGFloat(step) / 8
                let eased = 1 - (1 - progress) * (1 - progress)
                self.drawingOpacity = opacity == 1 ? 1 : initialOpacity * (1 - progress)
                self.emphasis = initialEmphasis + (emphasized - initialEmphasis) * eased
                self.needsDisplay = true
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard launcherState?.canShowRecentDocuments == true, drawingOpacity > 0 else { return }
        let emphasized = emphasis > 0 || isSelectedDocument
        let color: NSColor = increasesContrast ? .labelColor : (emphasized ? EditorPalette.buttonText : EditorPalette.secondary)
        if emphasized {
            EditorPalette.button.withAlphaComponent(drawingOpacity * (isSelectedDocument ? 1 : emphasis)).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6).fill()
        }
        EditorToolbarIcon.recentDocument.draw(in: bounds, color: color,
            opacity: (isEnabled ? 1 : 0.35) * drawingOpacity)
        if keyboardFocused {
            NSColor.controlAccentColor.withAlphaComponent(drawingOpacity).setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
            focus.lineWidth = increasesContrast ? 1.5 : 1
            focus.stroke()
        }
    }
}
