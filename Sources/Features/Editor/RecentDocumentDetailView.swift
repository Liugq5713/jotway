import AppKit
import SwiftUI

struct RecentDocumentDetailView: View {
    let document: RecentSavedDocument
    let state: LauncherViewState
    let focusTarget: EditorFocusTarget
    let send: (LauncherEvent) -> Void
    let text: String?
    let error: String?
    let isLoading: Bool
    let maximumHeight: CGFloat
    let composing: Bool
    let canInteract: () -> Bool
    let retry: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("recent_documents.title"))
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    ViewThatFits(in: .horizontal) {
                        Text(document.savedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
                        Color.clear.frame(width: 0, height: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(-1)
                .help(document.savedAt.formatted(date: .complete, time: .shortened))
                .accessibilityLabel(L10n.text("recent_documents.title") + ", "
                    + document.savedAt.formatted(date: .complete, time: .shortened))
                Text(L10n.text("recent_documents.position", (state.recentDocumentPosition ?? 0) + 1, state.recentDocuments.count))
                    .font(.system(size: 10).monospacedDigit()).fixedSize()
                    .accessibilityIdentifier("recent-document-position")
                if state.recentDocuments.count > 1 {
                    command("recent_documents.newer", symbol: "chevron.left", slot: 0,
                            enabled: state.canShowNewerRecentDocument) { send(.navigateRecentDocument(older: false)) }
                    command("recent_documents.older", symbol: "chevron.right", slot: 1,
                            enabled: state.canShowOlderRecentDocument) { send(.navigateRecentDocument(older: true)) }
                }
                command("recent_documents.close", symbol: "xmark", slot: 2, action: close)
            }
            .padding(.horizontal, 16).frame(height: 40)
            Rectangle().fill(.primary.opacity(0.06)).frame(height: 1).padding(.horizontal, 16)
            content
                .id(document.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: max(0, min(260, maximumHeight)))
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recent-document-detail")
        .onExitCommand {
            guard !composing, canInteract() else { return }
            close()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.text("recent_documents.loading"))
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
            .padding(16)
            .accessibilityElement(children: .combine)
        } else if let error {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: error).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                command("recent_documents.retry", symbol: nil, slot: 3, action: retry)
                    .frame(width: 76, height: 24)
                    .accessibilityIdentifier("recent-document-retry")
            }.padding(16)
        } else {
            let bodyText = text ?? ""
            ScrollView {
                Text(verbatim: bodyText.isEmpty ? L10n.text("recent_documents.empty_body") : bodyText)
                    .font(.system(size: 13)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .accessibilityIdentifier("recent-document-body")
        }
    }

    private func command(_ key: String, symbol: String?, slot: Int, enabled: Bool = true,
                         action: @escaping () -> Void) -> some View {
        RecentDocumentCommandControl(title: L10n.text(key), symbol: symbol,
            composing: composing, canInteract: canInteract, action: action, escape: close, enabled: enabled,
            register: { focusTarget.recentDocumentCommandButtons[slot] = $0 },
            unregister: { button in
                if focusTarget.recentDocumentCommandButtons[slot] === button {
                    focusTarget.recentDocumentCommandButtons[slot] = nil
                    if button.window?.firstResponder === button {
                        focusTarget.moveRecentDocumentCommandFocus(from: slot, forward: true, state: state)
                    }
                }
            },
            tab: { forward in focusTarget.moveRecentDocumentCommandFocus(from: slot, forward: forward, state: state) })
            .frame(width: symbol == nil ? nil : 22, height: 22)
            .accessibilityIdentifier("recent-document-command-\(slot)")
    }
}

struct RecentDocumentCommandControl: NSViewRepresentable {
    let title: String
    let symbol: String?
    let composing: Bool
    let canInteract: () -> Bool
    let action: () -> Void
    let escape: () -> Void
    var enabled: Bool = true
    var register: ((NSButton) -> Void)? = nil
    var unregister: ((NSButton) -> Void)? = nil
    var tab: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> RecentDocumentCommandButton {
        let button = RecentDocumentCommandButton()
        button.target = button
        button.action = #selector(RecentDocumentCommandButton.invoke)
        button.controlSize = .small
        return button
    }

    func updateNSView(_ button: RecentDocumentCommandButton, context: Context) {
        let hadFocus = button.window?.firstResponder === button
        button.title = symbol == nil ? title : ""
        button.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: title) }
        button.isBordered = symbol == nil
        button.bezelStyle = .rounded
        button.isEnabled = enabled && !composing
        button.canInteract = canInteract
        button.command = action
        button.escape = escape
        button.tab = tab
        button.unregister = unregister
        register?(button)
        button.toolTip = title
        button.setAccessibilityLabel(title)
        if hadFocus, !button.isEnabled, !composing, canInteract() { tab?(true) }
    }

    static func dismantleNSView(_ button: RecentDocumentCommandButton, coordinator: ()) {
        button.unregister?(button)
    }
}

@MainActor
final class RecentDocumentCommandButton: NSButton {
    var canInteract: () -> Bool = { true }
    var command: () -> Void = {}
    var escape: () -> Void = {}
    var tab: ((Bool) -> Void)?
    var unregister: ((NSButton) -> Void)?

    override var acceptsFirstResponder: Bool { isEnabled }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled, canInteract() else { return }
        invoke()
    }

    @objc func invoke() {
        guard isEnabled, canInteract() else { return }
        command()
    }

    override func keyDown(with event: NSEvent) {
        guard canInteract() else { return }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        // A navigation endpoint can become disabled while it still owns native focus.
        if event.keyCode == 0x30, modifiers.isEmpty || modifiers == .shift, let tab {
            if !event.isARepeat { tab(modifiers.isEmpty) }; return
        }
        if event.keyCode == 0x35, modifiers.isEmpty {
            if !event.isARepeat { escape() }
            return
        }
        guard isEnabled else { return }
        if modifiers.isEmpty, [UInt16(0x24), 0x4C, 0x31].contains(event.keyCode) {
            if !event.isARepeat { invoke() }
            return
        }
        super.keyDown(with: event)
    }
}
