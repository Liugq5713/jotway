import AppKit
import SwiftUI

/// A native control checks marked text before a click can resign the editor.
struct ModeControl: NSViewRepresentable {
    let focusTarget: EditorFocusTarget
    let state: LauncherViewState
    let send: (LauncherEvent) -> Void
    let isCardHovered: Bool
    let increasesContrast: Bool

    func makeNSView(context: Context) -> ModeButton {
        let button = ModeButton()
        button.isBordered = false
        button.title = ""
        button.focusRingType = .none
        button.target = button
        button.action = #selector(ModeButton.switchMode)
        focusTarget.modeButton = button
        return button
    }

    func updateNSView(_ button: ModeButton, context: Context) {
        button.focusTarget = focusTarget
        button.launcherState = state
        button.send = send
        button.increasesContrast = increasesContrast
        let name = L10n.text(state.mode == .quickInput ? "launcher.mode.sticky" : "launcher.mode.quick_input")
        button.toolTip = state.modeSwitchBlockReason ?? name
        button.setAccessibilityLabel(name)
        button.setAccessibilityHelp(button.toolTip)
        button.setAccessibilityIdentifier("launcher-mode-switch")
        button.isEnabled = state.modeSwitchBlockReason == nil
        button.isCardHovered = isCardHovered
        button.window?.invalidateCursorRects(for: button)
        button.needsDisplay = true
    }
}

@MainActor
final class ModeButton: NSButton {
    weak var focusTarget: EditorFocusTarget?
    var launcherState: LauncherViewState?
    var send: (LauncherEvent) -> Void = { _ in }
    var increasesContrast = false
    var isCardHovered = false {
        didSet {
            if isCardHovered != oldValue { refreshHoverFromMouseLocation() }
        }
    }
    private var hovered = false
    private var keyboardFocused = false
    private var iconIsRevealed = false
    private var iconOpacity: CGFloat = 0
    private var fadeTask: Task<Void, Never>?
    private var pressed = false
    private var pressTask: Task<Void, Never>?

    isolated deinit { fadeTask?.cancel(); pressTask?.cancel() }

    override var acceptsFirstResponder: Bool { isEnabled }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Do not call super: it may commit marked text before invoking the action.
        guard focusTarget?.textView?.hasMarkedText() != true else { return }
        switchMode()
    }

    @objc func switchMode() {
        guard let state = launcherState, state.modeSwitchBlockReason == nil,
              focusTarget?.textView?.hasMarkedText() != true else { return }
        showPressFeedback()
        send(.toggleMode)
        if state.lastEventSucceeded { focusTarget?.restoreEditorFocus() }
    }

    override func keyDown(with event: NSEvent) {
        guard focusTarget?.textView?.hasMarkedText() != true else { return }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers.isEmpty, [UInt16(0x24), 0x4C, 0x31].contains(event.keyCode) {
            if !event.isARepeat { switchMode() }
            return
        }
        if event.keyCode == 0x30 || event.keyCode == 0x35 {
            if event.keyCode == 0x35 {
                if !event.isARepeat { send(.cancel) }
                return
            }
            if event.keyCode == 0x30, modifiers == .shift, launcherState?.canChooseTarget == true,
               launcherState?.draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                focusTarget?.targetSelectorFocusRequest += 1
            } else if modifiers.isEmpty, focusTarget?.focusRecentDocument() == true {
                return
            } else if modifiers.isEmpty, focusTarget?.focusReview() == true {
                return
            } else if modifiers.isEmpty, focusTarget?.focusThinkingPrompt() == true {
                return
            } else { focusTarget?.restoreEditorFocus() }
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
        // A mode switch moves this control; replacing its tracking area need not deliver an exit.
        if let window, window.isVisible, !isHiddenOrHasHiddenAncestor {
            hovered = visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        } else {
            hovered = false
        }
        updateIconVisibility()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func cursorUpdate(with event: NSEvent) {
        (isEnabled ? NSCursor.pointingHand : .arrow).set()
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        updateIconVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        updateIconVisibility()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { keyboardFocused = true; updateIconVisibility() }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { keyboardFocused = false; updateIconVisibility() }
        return accepted
    }

    private func showPressFeedback() {
        pressTask?.cancel()
        pressed = true
        needsDisplay = true
        pressTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            self?.pressed = false
            self?.needsDisplay = true
        }
    }

    private func updateIconVisibility() {
        needsDisplay = true
        let revealed = isCardHovered || hovered || keyboardFocused
        guard revealed != iconIsRevealed else { return }
        iconIsRevealed = revealed
        fadeTask?.cancel()
        fadeTask = nil
        if revealed || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            iconOpacity = revealed ? 1 : 0
            return
        }
        // Fade only the drawing, keeping native focus, hit testing and tooltips intact.
        let startOpacity = iconOpacity
        fadeTask = Task { [weak self] in
            for step in 1...8 {
                do { try await Task.sleep(for: .milliseconds(15)) } catch { return }
                guard let self else { return }
                self.iconOpacity = startOpacity * (1 - CGFloat(step) / 8)
                self.needsDisplay = true
            }
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        guard iconOpacity > 0 else { return }
        let emphasized = isEnabled && (hovered || keyboardFocused)
        let opacity = iconOpacity * (isEnabled ? 1 : 0.4)
        if emphasized || pressed {
            let tile = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            (pressed ? EditorPalette.buttonActive : EditorPalette.button)
                .withAlphaComponent(opacity).setFill()
            tile.fill()
            (increasesContrast ? NSColor.labelColor : EditorPalette.accent)
                .withAlphaComponent(opacity * (increasesContrast ? 0.7 : 0.2)).setStroke()
            tile.lineWidth = increasesContrast ? 1 : 0.75
            tile.stroke()
        }
        let color: NSColor = increasesContrast
            ? (emphasized ? .controlAccentColor : .labelColor)
            : (emphasized ? EditorPalette.buttonText : EditorPalette.secondary)
        color.withAlphaComponent(opacity).setStroke()
        // Draw on a 22 pt grid: rounded outlines and an open fold remain clear at 1×.
        let path = NSBezierPath()
        path.lineWidth = 1.25
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        if launcherState?.mode == .quickInput {
            path.move(to: NSPoint(x: 7, y: 17.5))
            path.line(to: NSPoint(x: 15, y: 17.5))
            path.curve(to: NSPoint(x: 17, y: 15.5), controlPoint1: NSPoint(x: 16.1, y: 17.5),
                       controlPoint2: NSPoint(x: 17, y: 16.6))
            path.line(to: NSPoint(x: 17, y: 9))
            path.line(to: NSPoint(x: 12, y: 4.5))
            path.line(to: NSPoint(x: 7, y: 4.5))
            path.curve(to: NSPoint(x: 5, y: 6.5), controlPoint1: NSPoint(x: 5.9, y: 4.5),
                       controlPoint2: NSPoint(x: 5, y: 5.4))
            path.line(to: NSPoint(x: 5, y: 15.5))
            path.curve(to: NSPoint(x: 7, y: 17.5), controlPoint1: NSPoint(x: 5, y: 16.6),
                       controlPoint2: NSPoint(x: 5.9, y: 17.5))
            path.close()
            path.move(to: NSPoint(x: 12, y: 4.5))
            path.line(to: NSPoint(x: 12, y: 7.5))
            path.curve(to: NSPoint(x: 13.5, y: 9), controlPoint1: NSPoint(x: 12, y: 8.4),
                       controlPoint2: NSPoint(x: 12.6, y: 9))
            path.line(to: NSPoint(x: 17, y: 9))
            path.move(to: NSPoint(x: 8, y: 13.5))
            path.line(to: NSPoint(x: 14, y: 13.5))
            path.move(to: NSPoint(x: 8, y: 10.5))
            path.line(to: NSPoint(x: 10, y: 10.5))
        } else {
            path.appendRoundedRect(NSRect(x: 4.5, y: 6, width: 13, height: 10), xRadius: 2, yRadius: 2)
            path.move(to: NSPoint(x: 8, y: 9))
            path.line(to: NSPoint(x: 8, y: 13))
            path.move(to: NSPoint(x: 10.5, y: 11))
            path.line(to: NSPoint(x: 14, y: 11))
        }
        path.stroke()
        if keyboardFocused {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
            NSColor.controlAccentColor.withAlphaComponent(iconOpacity).setStroke()
            ring.lineWidth = increasesContrast ? 1.5 : 1
            ring.stroke()
        }
    }
}
