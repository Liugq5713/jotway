import SwiftUI

@MainActor
final class ClipboardModule: ActionModule {
    nonisolated static let moduleDescriptor = ActionDescriptor(
        id: "clipboard", title: "Clipboard", settingsName: "Clipboard", summary: "Search and copy local clipboard history.",
        titleKey: "clipboard.title", settingsNameKey: "clipboard.title", summaryKey: "clipboard.summary",
        systemImageName: "clipboard", tint: .blue,
        settingsGroup: .init(id: "local", title: "Local", order: 200, titleKey: "clipboard.group"),
        enablementPolicy: .userToggle(defaultEnabled: true), fallbackPriority: nil,
        intentHints: IntentHints(localKeywords: []),
        presentationPolicy: .returnToPreviousApplication, requiresExplicitSelection: true)
    let descriptor = ClipboardModule.moduleDescriptor
    let history: ClipboardHistory
    var onChange: (@MainActor () -> Void)?
    init(history: ClipboardHistory) { self.history = history }
    var state: ActionModuleState {
        .init(configurationRevision: 0, availability: .ready, summary: descriptor.localizedSummary, hasSavedConfiguration: true)
    }
    var settings: ActionSettings? { .init { AnyView(ClipboardSettingsView(history: self.history)) } }
    func refreshAvailability() {}
    func makeAction() -> any LauncherAction { ClipboardAction() }
}

/// Confirmation is owned by the local list, which freezes an item, never a query as payload.
private struct ClipboardAction: LauncherAction {
    let descriptor = ClipboardModule.moduleDescriptor
    func prepare(_ input: ActionInput) async throws -> PreparedAction {
        throw ActionFailure(localized: "clipboard.select_item")
    }
}

private struct ClipboardSettingsView: View {
    let history: ClipboardHistory
    @State private var confirmsClear = false
    var body: some View {
        Form {
            Toggle(L10n.text("clipboard.collect"), isOn: Binding(get: { history.enabled }, set: { history.setEnabled($0) }))
                .accessibilityIdentifier("clipboard-collection")
            Text(L10n.text("clipboard.privacy")).font(.caption).foregroundStyle(.secondary)
            Button(L10n.text("clipboard.clear"), role: .destructive) { confirmsClear = true }
                .accessibilityIdentifier("clipboard-clear")
            if let error = history.errorKey { Text(L10n.text(error)).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .confirmationDialog(L10n.text("clipboard.clear_confirm"), isPresented: $confirmsClear) {
            Button(L10n.text("clipboard.clear"), role: .destructive) { history.clear() }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: { Text(L10n.text("clipboard.clear_detail")) }
    }
}
