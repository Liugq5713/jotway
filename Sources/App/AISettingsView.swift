import SwiftUI

// Explicit keys keep command-line builds independent of Xcode's SwiftUI macro plugin.
private struct OpenAIServiceSettingsKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

private struct OpenWritingPreferencesKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var openAIServiceSettings: @MainActor () -> Void {
        get { self[OpenAIServiceSettingsKey.self] }
        set { self[OpenAIServiceSettingsKey.self] = newValue }
    }

    var openWritingPreferences: @MainActor () -> Void {
        get { self[OpenWritingPreferencesKey.self] }
        set { self[OpenWritingPreferencesKey.self] = newValue }
    }
}

struct AISettingsView: View {
    let appState: AppState
    var checkAPIKey: (() throws -> Bool)?
    // Set to true to restore the service cards and Personal Model disclosure.
    private let showsServiceSections = false
    @State private var personalExpanded = false

    private var activeTitle: String {
        if appState.models.hasActivationCode { return "Jotway AI" }
        if appState.models.isTextReady(.deep) { return L10n.text("settings.ai.personal.title") }
        return L10n.text("settings.ai.services.unconfigured")
    }

    var body: some View {
        Form {
            if showsServiceSections {
                Section(L10n.text("settings.ai.services.current")) {
                    Label(activeTitle, systemImage: "sparkles")
                        .font(.headline)
                    if !appState.models.hasActivationCode && !appState.models.isTextReady(.deep) {
                        Text(L10n.text("settings.ai.services.setup"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ActivationSettingsView(models: appState.models)
            }
            Section {
                if showsServiceSections {
                    DisclosureGroup(isExpanded: $personalExpanded) {
                        PersonalModelSettingsView(models: appState.models)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text("settings.ai.personal.title"))
                            if appState.models.hasActivationCode {
                                Text(L10n.text(appState.models.personalModel == nil
                                    ? "settings.ai.services.personal_unused" : "settings.ai.services.personal_saved"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disclosureGroupStyle(PromptHeaderDisclosureStyle())
                    .accessibilityIdentifier("ai-personal-disclosure")
                } else {
                    PersonalModelSettingsView(models: appState.models)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { personalExpanded = !appState.models.hasActivationCode }
        .onChange(of: appState.models.hasActivationCode) { _, hasCode in personalExpanded = !hasCode }
    }
}
