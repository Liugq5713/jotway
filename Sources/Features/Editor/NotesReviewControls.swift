import AppKit
import SwiftUI

/// Native buttons reject clicks before they can commit an unfinished input method composition.
struct NotesReviewControls: NSViewRepresentable {
    let focusTarget: EditorFocusTarget
    let state: LauncherViewState
    let send: (LauncherEvent) -> Void
    let isCardHovered: Bool
    let increasesContrast: Bool

    func makeNSView(context: Context) -> NotesReviewButtonsView { NotesReviewButtonsView() }

    static func dismantleNSView(_ view: NotesReviewButtonsView, coordinator: ()) {
        guard let target = view.buttons.first?.focusTarget,
              target.reviewButtons.first === view.buttons.first else { return }
        target.reviewButtons = []
    }

    func updateNSView(_ view: NotesReviewButtonsView, context: Context) {
        focusTarget.reviewButtons = view.buttons
        for button in view.buttons {
            button.focusTarget = focusTarget
            button.launcherState = state
            button.send = send
            button.isEnabled = state.modeSwitchBlockReason == nil && state.reviewAIBlockReason == nil
            button.isCardHovered = isCardHovered
            button.increasesContrast = increasesContrast
            button.state = state.showsReview ? .on : .off
            let title = L10n.text("notes.review.today")
            button.toolTip = state.reviewAIBlockReason ?? state.modeSwitchBlockReason ?? title
            button.setAccessibilityLabel(title)
            button.setAccessibilityHelp(button.toolTip)
            button.setAccessibilityIdentifier("launcher-review-today")
            button.refreshAppearance()
        }
    }
}

@MainActor
final class NotesReviewButtonsView: NSView {
    let buttons = [NotesReviewButton()]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: CGFloat(index) * 30, y: 0, width: 22, height: 22)
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: 22, height: 22) }
}

@MainActor
final class NotesReviewButton: NSButton {
    weak var focusTarget: EditorFocusTarget?
    var launcherState: LauncherViewState?
    var send: (LauncherEvent) -> Void = { _ in }
    var isCardHovered = false
    var increasesContrast = false
    private var hovered = false
    private var keyboardFocused = false

    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        focusRingType = .none
        target = self
        action = #selector(toggleReview)
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var canInteract: Bool {
        isEnabled && launcherState?.mode == .quickInput && launcherState?.modeSwitchBlockReason == nil
            && focusTarget?.textView?.hasMarkedText() != true
    }

    @objc private func toggleReview() {
        guard canInteract else { return }
        send(launcherState?.showsReview == true ? .closeReview : .toggleReview(.today))
        focusTarget?.restoreEditorFocus()
    }

    override func mouseDown(with event: NSEvent) { toggleReview() }

    override func keyDown(with event: NSEvent) {
        guard canInteract else { return }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers.isEmpty, [UInt16(0x24), 0x4C, 0x31].contains(event.keyCode) {
            if !event.isARepeat { toggleReview() }
            return
        }
        if event.keyCode == 0x35, modifiers.isEmpty {
            if !event.isARepeat { send(.cancel); focusTarget?.restoreEditorFocus() }
            return
        }
        if event.keyCode == 0x30, modifiers.isEmpty || modifiers == .shift {
            guard !event.isARepeat, let focusTarget else { return }
            let buttons = focusTarget.reviewButtons.filter(\.isEnabled)
            guard let index = buttons.firstIndex(where: { $0 === self }) else { return }
            let next = index + (modifiers == .shift ? -1 : 1)
            if buttons.indices.contains(next) { window?.makeFirstResponder(buttons[next]) }
            else if modifiers == .shift {
                if !focusTarget.focusRecentDocument(last: true) { focusTarget.focusModeControl() }
            } else if !focusTarget.focusThinkingPrompt() { focusTarget.restoreEditorFocus() }
            return
        }
        super.keyDown(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
        refreshAppearance()
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshAppearance() }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { keyboardFocused = true; needsDisplay = true }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { keyboardFocused = false; needsDisplay = true }
        return accepted
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    func refreshAppearance() {
        hovered = window.map { $0.isVisible && visibleRect.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        keyboardFocused = window?.firstResponder === self
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if canInteract { addCursorRect(bounds, cursor: .pointingHand) }
    }
    override func cursorUpdate(with event: NSEvent) { (canInteract ? NSCursor.pointingHand : .arrow).set() }

    override func draw(_ dirtyRect: NSRect) {
        guard isCardHovered || hovered || keyboardFocused || state == .on else { return }
        let emphasized = hovered || keyboardFocused || state == .on
        if emphasized {
            EditorPalette.button.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6).fill()
        }
        let color: NSColor = increasesContrast ? .labelColor : (emphasized ? EditorPalette.buttonText : EditorPalette.secondary)
        EditorToolbarIcon.review.draw(in: bounds, color: color, opacity: isEnabled ? 1 : 0.35)
        if keyboardFocused {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
            ring.lineWidth = increasesContrast ? 1.5 : 1
            ring.stroke()
        }
    }
}
