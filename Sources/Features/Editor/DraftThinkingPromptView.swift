import AppKit
import SwiftUI

struct DraftThinkingPromptView: View {
    let prompt: DraftThinkingPromptSession
    let focusTarget: EditorFocusTarget
    let state: LauncherViewState
    let maximumHeight: CGFloat
    let send: (LauncherEvent) -> Void
    let configure: () -> Void

    private var canInteract: Bool {
        !state.isComposingText && focusTarget.textView?.hasMarkedText() != true
    }
    private func perform(_ action: () -> Void) {
        guard canInteract else { return }
        action()
        focusTarget.restoreEditorFocus()
    }

    private var refreshKey: String {
        switch prompt.display {
        case .failed, .hostedFailure: "thinking.retry"
        default: "thinking.refresh"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(L10n.text("thinking.title"))
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                command(refreshKey, symbol: "arrow.clockwise", slot: 0,
                        disabled: prompt.display == .loading || prompt.blockReason != nil) {
                    perform { send(.requestThinkingPrompt) }
                }
                command("thinking.close", symbol: "xmark", slot: 1) {
                    perform { send(.closeThinkingPrompt) }
                }
            }
            .padding(.horizontal, 12).frame(height: 32)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("thinking.snapshot")).font(.system(size: 10)).foregroundStyle(.secondary)
                    switch prompt.display {
                    case .ready(let response):
                        InstantInsightContentView(text: response.text)
                    case .loading:
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L10n.text("thinking.loading"))
                        }
                    case .empty: Text(L10n.text("thinking.empty"))
                    case .hostedFailure(let problem):
                        Text(problem.message)
                        command("thinking.hosted_settings", symbol: nil, slot: 2) {
                            guard canInteract else { return }
                            send(.thinkingSettingsOpened)
                            configure()
                        }.frame(width: 150, height: 24)
                    case .failed(let code):
                        Text(L10n.text(code == .configuration ? "thinking.unconfigured"
                            : code == .inputTooLarge ? "thinking.too_large"
                            : code == .timeout ? "thinking.timeout" : "thinking.failed"))
                        if code == .configuration {
                            command("thinking.configure", symbol: nil, slot: 2) {
                                guard canInteract else { return }
                                send(.thinkingSettingsOpened)
                                configure()
                            }.frame(width: 150, height: 24)
                        }
                    case .closed: EmptyView()
                    }
                }
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
        .frame(height: max(0, min(180, maximumHeight)))
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("draft-thinking-prompt")
        .onDisappear { focusTarget.thinkingCommandButtons = [:] }
        .onChange(of: prompt.display) { _, value in
            guard value != .closed, value != .loading else { return }
            // Announce a fixed status, never focus or read the generated content automatically.
            if let view = focusTarget.textView {
                NSAccessibility.post(element: view, notification: .announcementRequested,
                    userInfo: [.announcement: L10n.text("thinking.updated"), .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            }
        }
    }

    private func command(_ key: String, symbol: String?, slot: Int, disabled: Bool = false,
                         action: @escaping () -> Void) -> some View {
        RecentDocumentCommandControl(title: L10n.text(key), symbol: symbol,
            composing: !canInteract || disabled, canInteract: { canInteract }, action: action,
            escape: { perform { send(.closeThinkingPrompt) } },
            register: { focusTarget.thinkingCommandButtons[slot] = $0 },
            tab: { forward in focusTarget.moveThinkingCommandFocus(from: slot, forward: forward, state: state) })
            .frame(width: symbol == nil ? nil : 22, height: 22)
            .accessibilityIdentifier("draft-thinking-\(slot)")
    }
}

struct DraftThinkingPromptControl: View {
    let focusTarget: EditorFocusTarget
    let state: LauncherViewState
    let isCardHovered: Bool
    let increasesContrast: Bool
    let send: (LauncherEvent) -> Void
    @State private var isHovered = false
    @State private var showsHelp = false

    private var helpText: String {
        (state.thinkingPrompt?.blockReason ?? L10n.text("thinking.open")) + " (⌘J)"
    }

    var body: some View {
        DraftThinkingPromptNativeControl(focusTarget: focusTarget, state: state,
            isCardHovered: isCardHovered, increasesContrast: increasesContrast,
            helpText: helpText, send: { event in
                dismissHelp()
                send(event)
            })
            .onHover { hovering in
                isHovered = hovering
                if !hovering { showsHelp = false }
            }
            .task(id: isHovered) {
                guard isHovered else { return }
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                guard !Task.isCancelled, isHovered else { return }
                showsHelp = true
            }
            .overlay(alignment: .topLeading) {
                if showsHelp {
                    Text(verbatim: helpText)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: EditorPalette.text))
                        .frame(maxWidth: 220, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color(nsColor: EditorPalette.surface),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(increasesContrast ? Color.primary : Color(nsColor: EditorPalette.outline),
                                              lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                        .alignmentGuide(.top) { $0[.bottom] + 6 }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onChange(of: state.draftContent) { _, _ in dismissHelp() }
            .onChange(of: state.panelSessionID) { _, _ in dismissHelp() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
                dismissHelp()
            }
            .onDisappear { dismissHelp() }
    }

    private func dismissHelp() {
        isHovered = false
        showsHelp = false
    }
}

private struct DraftThinkingPromptNativeControl: NSViewRepresentable {
    let focusTarget: EditorFocusTarget
    let state: LauncherViewState
    let isCardHovered: Bool
    let increasesContrast: Bool
    let helpText: String
    let send: (LauncherEvent) -> Void

    func makeNSView(context: Context) -> DraftThinkingPromptButton { DraftThinkingPromptButton() }
    static func dismantleNSView(_ button: DraftThinkingPromptButton, coordinator: ()) {
        guard let focusTarget = button.focusTarget, focusTarget.thinkingButton === button else { return }
        focusTarget.thinkingButton = nil
    }
    func updateNSView(_ button: DraftThinkingPromptButton, context: Context) {
        focusTarget.thinkingButton = button
        button.focusTarget = focusTarget
        button.launcherState = state
        button.send = send
        button.isEnabled = state.thinkingPrompt?.blockReason == nil
        button.setAccessibilityLabel(L10n.text("thinking.open"))
        button.setAccessibilityHelp(helpText)
        button.setAccessibilityIdentifier("launcher-thinking-prompt")
        button.increasesContrast = increasesContrast
        button.isCardHovered = isCardHovered
        button.refreshAppearance()
    }
}

@MainActor
final class DraftThinkingPromptButton: NSButton {
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
    private var hoverTrackingArea: NSTrackingArea?
    private var iconIsRevealed = false
    private var opacity: CGFloat = 0
    private var fade: Task<Void, Never>?
    override init(frame: NSRect) {
        super.init(frame: frame)
        title = ""; isBordered = false; focusRingType = .none
        target = self; action = #selector(invoke)
    }
    required init?(coder: NSCoder) { nil }
    isolated deinit { fade?.cancel() }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func invoke() {
        guard isEnabled, focusTarget?.textView?.hasMarkedText() != true, launcherState?.isComposingText != true else { return }
        send(.requestThinkingPrompt)
        focusTarget?.restoreEditorFocus()
    }
    override func mouseDown(with event: NSEvent) { invoke() }
    override func keyDown(with event: NSEvent) {
        guard focusTarget?.textView?.hasMarkedText() != true else { return }
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if mods.isEmpty, [UInt16(0x24), 0x4C, 0x31].contains(event.keyCode) {
            if !event.isARepeat { invoke() }; return
        }
        if event.keyCode == 0x35, mods.isEmpty { if !event.isARepeat { send(.cancel) }; return }
        if event.keyCode == 0x30, mods.isEmpty || mods == .shift {
            guard !event.isARepeat, let focusTarget, let state = launcherState else { return }
            if mods == .shift {
                if !focusTarget.focusReview(last: true), !focusTarget.focusRecentDocument(last: true) {
                    focusTarget.focusModeControl()
                }
            } else { focusTarget.moveThinkingCommandFocus(from: -1, forward: true, state: state) }
            return
        }
        super.keyDown(with: event)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        hoverTrackingArea = area
        addTrackingArea(area)
        refreshHoverFromMouseLocation()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshHoverFromMouseLocation()
    }
    private func refreshHoverFromMouseLocation() {
        // Moving or hiding the card may not deliver a matching mouseExited event.
        if let window, window.isVisible, !isHiddenOrHasHiddenAncestor {
            hovered = visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        } else {
            hovered = false
        }
        refreshAppearance()
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; refreshAppearance() }
    override func mouseExited(with event: NSEvent) { hovered = false; refreshAppearance() }
    override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); refreshAppearance(); return result }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        Task { @MainActor [weak self] in self?.refreshAppearance() }
        return result
    }
    func refreshAppearance() {
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        let revealed = isCardHovered || hovered || window?.firstResponder === self
        guard revealed != iconIsRevealed else { return }
        iconIsRevealed = revealed
        fade?.cancel()
        fade = nil
        if revealed || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            opacity = revealed ? 1 : 0; needsDisplay = true
        } else {
            let initial = opacity
            fade = Task { [weak self] in
                for step in 1...8 {
                    do { try await Task.sleep(for: .milliseconds(15)) } catch { return }
                    guard let self else { return }
                    self.opacity = initial * (1 - CGFloat(step) / 8); self.needsDisplay = true
                }
            }
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled, opacity > 0 { addCursorRect(bounds, cursor: .pointingHand) }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard opacity > 0 else { return }
        let focused = window?.firstResponder === self
        let emphasized = hovered || focused
        if emphasized {
            EditorPalette.button.withAlphaComponent(opacity).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6).fill()
        }
        let color: NSColor = increasesContrast ? .labelColor : (emphasized ? EditorPalette.buttonText : EditorPalette.secondary)
        EditorToolbarIcon.thinkingPrompt.draw(in: bounds, color: color,
            opacity: opacity * (isEnabled ? 1 : 0.35))
        if focused {
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
            path.lineWidth = increasesContrast ? 1.5 : 1; path.stroke()
        }
    }
}
