import AppKit
import SwiftUI

/// Mouse-only hit area. SwiftUI retains the capsule's drawing, keyboard focus and accessibility.
struct TargetCapsulePointer: NSViewRepresentable {
    let focusTarget: EditorFocusTarget
    let state: LauncherViewState
    let activate: () -> Void

    func makeNSView(context: Context) -> TargetCapsulePointerView { TargetCapsulePointerView() }

    func updateNSView(_ view: TargetCapsulePointerView, context: Context) {
        view.focusTarget = focusTarget
        view.launcherState = state
        view.activate = activate
    }

    /// Shared by mouse and the named accessibility action; the session still owns final validation.
    @MainActor
    static func activate(focusTarget: EditorFocusTarget, state: LauncherViewState,
                         send: (LauncherEvent) -> Void, clearCapsuleFocus: () -> Void) {
        guard focusTarget.textView?.hasMarkedText() != true, !state.isComposingText,
              !state.showsReview, state.mode == .quickInput, state.modeSwitchBlockReason == nil,
              !state.isTemplateMenuVisible,
              !state.draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if state.isIntentCandidateMenuVisible {
            send(.candidateMenuChanged(false))
            clearCapsuleFocus()
            focusTarget.restoreEditorFocus()
            return
        }
        guard state.canConfirm else { return }
        send(.confirm(.button))
    }
}

@MainActor
final class TargetCapsulePointerView: NSView {
    weak var focusTarget: EditorFocusTarget?
    var launcherState: LauncherViewState?
    var activate: () -> Void = {}

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func isAccessibilityElement() -> Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHiddenOrHasHiddenAncestor else { return nil }
        let local = convert(point, from: superview)
        let radius = min(bounds.width, bounds.height) / 2
        guard bounds.width > 0, bounds.height > 0,
              NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).contains(local) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        // Never call super: a native button's default handling could commit marked text first.
        guard focusTarget?.textView?.hasMarkedText() != true,
              launcherState?.isComposingText == false else { return }
        activate()
    }
}
