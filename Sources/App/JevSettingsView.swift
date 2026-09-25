import SwiftUI

struct JevSettingsView: View {
    let appState: AppState
    @State private var settings: JevSettings
    @State private var apiKey = ""
    @State private var corrections: [IntentCorrection] = []
    @State private var rules: [IntentRule] = []
    @State private var newPhrase = ""
    @State private var newActionID = ""
    @FocusState private var isEditingKey: Bool

    init(appState: AppState, settings: JevSettings = .shared) {
        self.appState = appState
        _settings = State(initialValue: settings)
    }

    var body: some View {
        Group {
            keySection
            rulesSection
            correctionsSection
        }
        .onAppear {
            corrections = appState.recentIntentCorrections()
            rules = appState.intentRules
            if newActionID.isEmpty { newActionID = enabledActions.first?.id ?? "" }
        }
    }

    private var enabledActions: [ActionDescriptor] {
        appState.actionRegistry.executionSnapshots().map(\.descriptor)
    }

    private func actionTitle(_ id: String) -> String {
        appState.actionRegistry.descriptor(for: id)?.localizedTitle ?? id
    }

    @ViewBuilder private var rulesSection: some View {
        Section {
            if rules.isEmpty {
                Text(L10n.text("jev.rules.empty"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(rules) { rule in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.phrase).font(.callout).lineLimit(1)
                            Text(L10n.text("jev.rules.target", actionTitle(rule.actionID)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            appState.removeIntentRule(id: rule.id)
                            rules = appState.intentRules
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.text("jev.rules.delete"))
                    }
                    .padding(.vertical, 1)
                }
            }
            TextField(L10n.text("jev.rules.phrase"), text: $newPhrase,
                      prompt: Text(L10n.text("jev.rules.phrase_example")))
                .textFieldStyle(.roundedBorder)
                .onSubmit(addRule)
            HStack(spacing: 12) {
                Picker(L10n.text("jev.rules.target_action"), selection: $newActionID) {
                    ForEach(enabledActions, id: \.id) { action in
                        Text(action.localizedTitle).tag(action.id)
                    }
                }
                Spacer(minLength: 0)
                Button(L10n.text("jev.rules.add"), action: addRule)
                    .disabled(newPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newActionID.isEmpty)
            }
        } header: {
            Text(L10n.text("jev.rules.section"))
        } footer: {
            Text(L10n.text("jev.rules.help"))
        }
    }

    private func addRule() {
        let phrase = newPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty, !newActionID.isEmpty else { return }
        appState.addIntentRule(phrase: phrase, actionID: newActionID)
        rules = appState.intentRules
        newPhrase = ""
    }

    private var keySection: some View {
        Section {
            settingRow(settings.status) {
                SecureField(settings.hasAPIKey ? L10n.text("settings.key.replace_placeholder") : "Jev API Key", text: Binding(
                    get: { apiKey },
                    set: {
                        apiKey = $0
                        settings.beginEditingAPIKey()
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .accessibilityLabel("Jev API Key")
                .focused($isEditingKey)
                .onSubmit(saveKey)
            }
            HStack {
                Button(settings.hasAPIKey ? L10n.text("jev.key.replace") : L10n.text("jev.key.save"), action: saveKey)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(L10n.text("settings.key.remove"), role: .destructive) {
                    if settings.removeAPIKey() { apiKey = "" }
                }
                .disabled(!settings.hasAPIKey)
                Spacer(minLength: 12)
                Link(L10n.text("jev.key.get"), destination: URL(string: "https://console.typesafe.ai/")!)
            }
            settingRow(L10n.text("jev.connection.help")) {
                HStack(spacing: 12) {
                    Text(L10n.text("settings.connection.verify"))
                    Spacer(minLength: 12)
                    if settings.isTesting { ProgressView().controlSize(.small) }
                    Button(settings.isTesting ? L10n.text("settings.connection.testing") : L10n.text("settings.connection.test")) {
                        settings.testConnection()
                    }
                    .disabled(settings.isTesting || !settings.hasAPIKey || !apiKey.isEmpty)
                }
            }
            if let message = settings.connectionMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        } header: {
            Text(L10n.text("jev.service"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("jev.key.storage_help"))
                Text(L10n.text("jev.service.help"))
            }
        }
        .onAppear { settings.refreshKeyStatus() }
        .onChange(of: isEditingKey) { if isEditingKey { settings.beginEditingAPIKey() } }
        .onDisappear {
            apiKey = ""
            settings.invalidateConnectionTest()
        }
    }

    @ViewBuilder private var correctionsSection: some View {
        Section {
            if corrections.isEmpty {
                Text(L10n.text("jev.corrections.empty", IntentCorrection.retentionLimit))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(corrections, id: \.id) { correction in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(correction.text).font(.callout).lineLimit(1)
                        Text(L10n.text("jev.corrections.changed",
                                       correctionTitle(correction.jevTargetID, legacy: correction.jevLabel),
                                       correctionTitle(correction.chosenTargetID, legacy: correction.chosenLabel)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 1)
                }
                Button(L10n.text("jev.corrections.clear"), role: .destructive) {
                    appState.clearIntentCorrections()
                    corrections = []
                }
            }
        } header: {
            Text(L10n.text("jev.corrections.section"))
        } footer: {
            Text(L10n.text("jev.corrections.help"))
        }
    }

    private func saveKey() {
        if settings.saveAPIKey(apiKey) { apiKey = "" }
    }

    private func correctionTitle(_ id: String?, legacy: String) -> String {
        guard let id else { return legacy }
        return appState.actionRegistry.descriptor(for: id)?.localizedTitle ?? (legacy == id ? id : legacy)
    }
}
