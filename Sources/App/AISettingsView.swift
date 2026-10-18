import SwiftUI

extension EnvironmentValues {
    @Entry var openAIServiceSettings: @MainActor () -> Void = {}
    @Entry var openWritingPreferences: @MainActor () -> Void = {}
}

struct AISettingsView: View {
    let appState: AppState
    var checkAPIKey: (() throws -> Bool)?
    @State private var personalExpanded = false

    private var activeTitle: String {
        if appState.models.hasActivationCode { return "Jotway AI" }
        if appState.models.isTextReady(.deep) { return L10n.text("settings.ai.personal.title") }
        return L10n.text("settings.ai.services.unconfigured")
    }

    var body: some View {
        Form {
            Section(L10n.text("settings.ai.services.current")) {
                Label(activeTitle, systemImage: "sparkles")
                    .font(.headline)
                Text(L10n.text(appState.models.hasActivationCode ? "settings.ai.services.hosted" : "settings.ai.services.personal"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ActivationSettingsView(models: appState.models)
            Section {
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
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { personalExpanded = !appState.models.hasActivationCode }
        .onChange(of: appState.models.hasActivationCode) { _, hasCode in personalExpanded = !hasCode }
    }
}

struct PersonalModelSettingsView: View {
    let models: ModelConfiguration
    @State private var draft = PersonalModelConfiguration()
    @State private var key = ""
    @State private var message: String?
    @State private var issue: String?
    @State private var testing = false
    @State private var testTask: Task<Void, Never>?
    private var edited: Bool {
        draft != (models.personalModel ?? .init()) || !key.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text(models.hasActivationCode ? "settings.ai.personal.hosted_active" : "settings.ai.personal.help"))
                .font(.caption).foregroundStyle(.secondary)
            Picker(L10n.text("settings.ai.personal.service"), selection: Binding(
                get: { draft.service }, set: { service in
                    guard service != draft.service else { return }
                    draft.service = service; draft.baseURL = service.defaultBaseURL
                    draft.model = ""; key = ""; invalidate()
                })) {
                ForEach(PersonalModelConfiguration.Service.allCases, id: \.self) { service in
                    Text(service.title).tag(service)
                }
            }
            TextField(L10n.text("settings.ai.personal.url"), text: $draft.baseURL,
                      prompt: Text(draft.service == .claude ? "https://api.anthropic.com/v1" : "https://api.example.com/v1"))
                .autocorrectionDisabled()
                .accessibilityIdentifier("personal-ai-url")
            Text(L10n.text("settings.ai.personal.url_help")).font(.caption).foregroundStyle(.secondary)
            TextField(L10n.text("settings.ai.personal.model"), text: $draft.model)
                .autocorrectionDisabled()
                .accessibilityIdentifier("personal-ai-model")
            SecureField("API Key", text: $key,
                        prompt: Text(L10n.text(models.hasPersonalKey ? "settings.ai.personal.key_saved" : "settings.ai.personal.key_enter")))
                .accessibilityIdentifier("personal-ai-key")
            HStack {
                Button(L10n.text("common.save")) { save() }.disabled(!edited || testing)
                if models.hasPersonalKey {
                    Button(L10n.text("settings.key.remove"), role: .destructive) {
                        invalidate()
                        do { try models.removePersonalKey(); key = ""; issue = nil }
                        catch { issue = error.localizedDescription }
                    }.disabled(testing)
                }
                Spacer()
                Button(L10n.text(testing ? "settings.connection.testing" : "settings.connection.test")) { test() }
                    .disabled(testing || edited || !models.isTextReady(.deep))
            }
            Text(L10n.text(models.hasActivationCode ? "settings.ai.personal.test_hosted" : "settings.ai.personal.privacy"))
                .font(.caption).foregroundStyle(.secondary)
            if let issue = issue ?? models.bindingIssue { Text(issue).font(.caption).foregroundStyle(.red) }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .onAppear { draft = models.personalModel ?? .init() }
        .onChange(of: draft) { invalidate() }
        .onChange(of: key) { invalidate() }
        .onChange(of: models.version(.deep)) { invalidate() }
        .onDisappear { invalidate(); key = "" }
    }
    private func invalidate() {
        testTask?.cancel(); testTask = nil; testing = false; message = nil
    }
    private func save() {
        invalidate(); issue = nil
        do {
            try models.savePersonalModel(draft, key: key)
            draft = models.personalModel ?? draft; key = ""
        } catch { issue = error.localizedDescription }
    }
    private func test() {
        invalidate(); issue = nil; testing = true
        let version = models.version(.deep)
        testTask = Task { @MainActor in
            let result: String
            do {
                let invocation = try models.text(.deep)
                var request = invocation.request("Reply with OK.", "This is a connection test. Reply briefly.")
                request.maximumTokens = 128; request.maximumTokensForThinkingModel = 16_384; request.timeout = 30
                _ = try await invocation.call(request, loggingPurpose: .connectionTest)
                result = L10n.text("settings.ai.connection.succeeded_title", models.hasActivationCode ? "Jotway AI" : draft.model)
            } catch { result = error.localizedDescription }
            guard !Task.isCancelled, version == models.version(.deep) else { return }
            message = result; testing = false; testTask = nil
        }
    }
}
