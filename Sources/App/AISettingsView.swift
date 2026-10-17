import SwiftUI

struct AISettingsView: View {
    let appState: AppState
    var checkAPIKey: (() throws -> Bool)?

    var body: some View {
        Form {
            Section(L10n.text("thinking.settings.title")) {
                Toggle(L10n.text("thinking.settings.automatic"), isOn: Binding(
                    get: { appState.automaticDraftThinkingPromptsEnabled },
                    set: { appState.automaticDraftThinkingPromptsEnabled = $0 }))
                Text(L10n.text("thinking.settings.help")).font(.caption).foregroundStyle(.secondary)
            }
            ModelCapabilitySettingsView(models: appState.models, capability: .fast)
            ModelCapabilitySettingsView(models: appState.models, capability: .deep)
            ModelServiceSettingsView(models: appState.models)
            Section(L10n.text("settings.ai.embedding")) {
                if let status = appState.models.statuses.first(where: { $0.id == .embedding }) {
                    LabeledContent(status.title, value: L10n.text(status.ready ? "settings.ai.ready" : "settings.ai.not_ready"))
                    Text(status.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ModelCapabilitySettingsView: View {
    let models: ModelConfiguration
    let capability: ModelConfiguration.Capability
    @State private var messages: [ModelConfiguration.TextModel: String] = [:]
    @State private var testing: ModelConfiguration.TextModel?
    @State private var testTask: Task<Void, Never>?

    private var binding: ModelConfiguration.TextBinding { models.binding(capability) }
    var body: some View {
        Section(L10n.text(capability == .fast ? "settings.ai.fast" : "settings.ai.deep")) {
            Picker(L10n.text("settings.ai.primary"), selection: Binding(
                get: { binding.primary }, set: { selected in
                    var next = binding
                    if next.fallback == selected { next.fallback = next.primary }
                    next.primary = selected
                    models.setBinding(next, for: capability)
                })) {
                choices(includeSaved: binding.primary)
            }
            Picker(L10n.text("settings.ai.fallback"), selection: Binding(
                get: { binding.fallback }, set: { selected in
                    var next = binding; next.fallback = selected
                    models.setBinding(next, for: capability)
                })) {
                Text(L10n.text("settings.ai.none")).tag(Optional<ModelConfiguration.TextModel>.none)
                ForEach(models.choices(capability).filter { $0 != binding.primary }, id: \.self) { model in
                    Text(models.title(model, capability: capability)).tag(Optional(model))
                }
                if let saved = binding.fallback, !models.choices(capability).contains(saved) {
                    Text(models.title(saved, capability: capability)).tag(Optional(saved))
                }
            }
            Button(L10n.text("settings.ai.swap")) { models.swap(capability) }
                .disabled(binding.fallback == nil)
            if let issue = models.bindingIssue { Text(issue).foregroundStyle(.red) }
            modelStatus(binding.primary, role: "settings.ai.primary")
            if let fallback = binding.fallback { modelStatus(fallback, role: "settings.ai.fallback") }
            Text(L10n.text(capability == .fast ? "settings.ai.fast_help" : "settings.ai.deep_help"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: models.version(capability)) { invalidate() }
        .onDisappear { invalidate() }
    }
    @ViewBuilder private func choices(includeSaved saved: ModelConfiguration.TextModel) -> some View {
        ForEach(models.choices(capability), id: \.self) { model in
            Text(models.title(model, capability: capability)).tag(model)
        }
        if !models.choices(capability).contains(saved) { Text(models.title(saved, capability: capability)).tag(saved) }
    }
    private func modelStatus(_ model: ModelConfiguration.TextModel, role: String) -> some View {
        let ready = (try? models.configuration(model, capability: capability)) != nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.text(role) + ": " + models.title(model, capability: capability))
                Spacer()
                Text(L10n.text(ready ? "settings.ai.ready" : "settings.ai.not_ready"))
                    .foregroundStyle(.secondary)
                Button(L10n.text(testing == model ? "settings.connection.testing" : "settings.connection.test")) { test(model) }
                    .disabled(!ready || testing != nil)
            }
            if let message = messages[model] { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func invalidate() { testTask?.cancel(); testTask = nil; testing = nil; messages = [:] }
    private func test(_ model: ModelConfiguration.TextModel) {
        let version = models.version(capability)
        testing = model; messages[model] = nil
        testTask = Task { @MainActor in
            let message: String
            do {
                let invocation = try ModelTextInvocation.direct(models.configuration(model, capability: capability))
                var request = invocation.request("Reply with OK.", "This is a connection test. Reply briefly.")
                request.maximumTokens = 32; request.maximumTokensForThinkingModel = 16_384; request.timeout = 30
                request.streaming = capability == .deep
                let frozen = request
                _ = try await ModelDeadline.run(until: .now.advanced(by: .seconds(30))) {
                    try await invocation.call(frozen, loggingPurpose: .connectionTest)
                }
                message = L10n.text("settings.ai.connection.succeeded_title", models.title(model, capability: capability))
            } catch { message = error.localizedDescription }
            guard !Task.isCancelled, version == models.version(capability) else { return }
            messages[model] = message; testing = nil; testTask = nil
        }
    }
}

struct ModelServiceSettingsView: View {
    let models: ModelConfiguration
    var body: some View {
        Section(L10n.text("settings.ai.services")) {
            ModelServiceKeyView(models: models, provider: .deepSeek, title: "DeepSeek",
                                keyURL: URL(string: "https://platform.deepseek.com/api_keys")!)
            ModelServiceKeyView(models: models, provider: .moonshot, title: "Moonshot",
                                keyURL: URL(string: "https://platform.moonshot.cn/console/api-keys")!)
            Text(L10n.text("settings.ai.fallback_privacy")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ModelServiceKeyView: View {
    let models: ModelConfiguration
    let provider: APIKeyStore.Provider
    let title: String
    let keyURL: URL
    @State private var key = ""
    @State private var issue: String?
    @FocusState private var focused: Bool
    var body: some View {
        let _ = models.revision
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ServiceKeyField(accessibilityTitle: title, keyURL: keyURL,
                hasKey: (try? models.loadKey(provider)) != nil, text: $key, isFocused: $focused, save: save)
            if (try? models.loadKey(provider)) != nil {
                Button(L10n.text("settings.key.remove"), role: .destructive) {
                    do { try models.removeKey(for: provider); issue = nil; key = "" }
                    catch { issue = error.localizedDescription }
                }
            }
            if let issue { Text(issue).foregroundStyle(.red) }
        }
        .onDisappear { key = "" }
    }
    private func save() {
        do { try models.saveKey(key, for: provider); key = ""; issue = nil; focused = false }
        catch { issue = error.localizedDescription }
    }
}
