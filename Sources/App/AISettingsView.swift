import SwiftUI

struct AISettingsView: View {
    let appState: AppState
    var checkAPIKey: (() throws -> Bool)?
    @State private var apiKey = ""
    @State private var hasAPIKey = false
    @State private var keyIssue: String?
    @State private var showsDetails = false
    @FocusState private var isEditingKey: Bool

    private var isAvailable: Bool { appState.onTestAIConnection != nil }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    sourceChoices
                    if !isAvailable {
                        Text(L10n.text("settings.ai.unavailable"))
                            .font(.callout).foregroundStyle(.secondary)
                    } else if let source = appState.selectedAISource {
                        if !source.models.isEmpty { modelPicker(source) }
                        if let keyURL = source.keyURL {
                            ServiceKeyField(accessibilityTitle: L10n.text("settings.key.accessibility", source.title), keyURL: keyURL,
                                            hasKey: hasAPIKey, text: Binding(
                                                get: { apiKey },
                                                set: { apiKey = $0; appState.invalidateAIConnectionTest() }
                                            ), isFocused: $isEditingKey, save: saveKey)
                        }
                        if let keyIssue {
                            Label(keyIssue, systemImage: "exclamationmark.circle")
                                .font(.callout).foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.updatesFrequently)
                        }
                        connectionActions(source)
                        if let message = appState.aiConnectionMessage {
                            Text(message)
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.updatesFrequently)
                        }
                        details(source)
                    } else {
                        Text(L10n.text("settings.ai.source_unregistered", appState.aiSource))
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: refreshKeyStatus)
        .onChange(of: appState.selectedAISource?.id) {
            apiKey = ""
            isEditingKey = false
            refreshKeyStatus()
        }
        .onChange(of: isEditingKey) { if isEditingKey { appState.invalidateAIConnectionTest() } }
        .onDisappear { apiKey = "" }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            Text(L10n.text("settings.ai.source"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if isAvailable, appState.selectedAISource?.keyURL != nil {
                ServiceKeyStatus(hasKey: hasAPIKey)
            }
        }
    }

    private var sourceChoices: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
            ForEach(appState.aiSources) { source in
                Button {
                    appState.setAISource(source.id)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.title).font(.callout.weight(.semibold))
                            if let model = fixedModelTitle(source) {
                                Text(model).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: appState.aiSource == source.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(appState.aiSource == source.id ? Color.accentColor : .secondary.opacity(0.35))
                            .accessibilityHidden(true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(appState.aiSource == source.id ? Color.accentColor.opacity(0.06) : .primary.opacity(0.025),
                                in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(appState.aiSource == source.id ? Color.accentColor.opacity(0.45) : .primary.opacity(0.08))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("settings.ai.provider") + ": " + source.title)
                .accessibilityAddTraits(appState.aiSource == source.id ? .isSelected : [])
            }
        }
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.5)
    }

    private func modelPicker(_ source: AIProviderPlugin.Source) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("settings.ai.model")).font(.callout.weight(.medium))
            Menu {
                Picker(L10n.text("settings.ai.model"), selection: Binding(
                    get: { appState.aiModel ?? "" }, set: { appState.setAIModel($0) }
                )) {
                    ForEach(source.models, id: \.id) { model in
                        Text(model.title).tag(model.id)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 12) {
                    Text(source.models.first { $0.id == appState.aiModel }?.title ?? L10n.text("settings.ai.model"))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.1))
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel(L10n.text("settings.ai.model"))
            .accessibilityValue(source.models.first { $0.id == appState.aiModel }?.title ?? "")
        }
    }

    private func connectionActions(_ source: AIProviderPlugin.Source) -> some View {
        HStack(spacing: 12) {
            Button {
                isEditingKey = false
                Task { await appState.testAIConnection() }
            } label: {
                HStack(spacing: 7) {
                    if appState.isTestingAIConnection {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "bolt.horizontal")
                    }
                    Text(L10n.text(appState.isTestingAIConnection ? "settings.connection.testing" : "settings.connection.test"))
                }
            }
            .buttonStyle(ServiceSettingsButtonStyle())
            .disabled(appState.isTestingAIConnection || (source.keyURL != nil && (!hasAPIKey || !apiKey.isEmpty)))
            Spacer(minLength: 0)
            if source.keyURL != nil, hasAPIKey {
                Button(L10n.text("settings.key.remove"), role: .destructive, action: removeKey)
                    .buttonStyle(.plain)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
        }
    }

    private func details(_ source: AIProviderPlugin.Source) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sourceDetail(source)).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup(isExpanded: $showsDetails) {
                VStack(alignment: .leading, spacing: 8) {
                    if source.keyURL != nil { Text(L10n.text("settings.key.storage_help")) }
                    Text(L10n.text("settings.ai.connection.help"))
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            } label: {
                Text(L10n.text("settings.service.details"))
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func fixedModelTitle(_ source: AIProviderPlugin.Source) -> String? {
        guard source.models.isEmpty else { return nil }
        switch source.id {
        case "deepSeek": return "deepseek-flash"
        case "moonshot": return "kimi-k2"
        default: return nil
        }
    }

    private func sourceDetail(_ source: AIProviderPlugin.Source) -> String {
        switch source.id {
        case "deepSeek": L10n.text("settings.ai.detail.deepseek")
        case "moonshot": L10n.text("settings.ai.detail.moonshot")
        default: source.detail
        }
    }

    private func refreshKeyStatus() {
        hasAPIKey = false
        keyIssue = nil
        guard isAvailable, let hasKey = appState.selectedAISource?.hasKey else { return }
        do { hasAPIKey = try (checkAPIKey ?? hasKey)() }
        catch { keyIssue = error.localizedDescription }
    }

    private func saveKey() {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let save = appState.selectedAISource?.saveKey else { return }
        appState.invalidateAIConnectionTest()
        do {
            try save(value)
            apiKey = ""
            isEditingKey = false
            hasAPIKey = true
            keyIssue = nil
        } catch { keyIssue = error.localizedDescription }
    }

    private func removeKey() {
        guard let remove = appState.selectedAISource?.removeKey else { return }
        appState.invalidateAIConnectionTest()
        do {
            try remove()
            apiKey = ""
            isEditingKey = false
            hasAPIKey = false
            keyIssue = nil
        } catch { keyIssue = error.localizedDescription }
    }
}
