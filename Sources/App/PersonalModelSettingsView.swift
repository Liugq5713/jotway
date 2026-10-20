import SwiftUI

struct PersonalModelSettingsView: View {
    let models: ModelConfiguration
    @State private var draft = PersonalModelConfiguration()
    @State private var provider: PersonalAIProvider = .custom
    @State private var key = ""
    @State private var advancedExpanded = false
    @State private var manualModel = true
    @State private var issue: String?
    @State private var testMessage: String?
    @State private var testFailed = false
    @State private var testID: UUID?
    @State private var testTask: Task<Void, Never>?
    @State private var catalog: PersonalModelCatalog.Result?
    @State private var catalogIssue: String?
    @State private var catalogID: UUID?
    @State private var catalogTask: Task<Void, Never>?

    private var initialDraft: PersonalModelConfiguration {
        models.personalModel ?? .init(baseURL: PersonalAIProvider.deepSeek.baseURL)
    }
    private var edited: Bool {
        draft != initialDraft || !key.isEmpty
    }
    private var testing: Bool { testID != nil }
    private var loadingModels: Bool { catalogID != nil }
    private var testProvider: String {
        models.hasActivationCode ? "Jotway AI" : PersonalAIProvider.matching(models.personalModel ?? draft).title
    }
    private var testModel: String { models.deepModel ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if models.hasActivationCode {
                statusMessage(L10n.text("settings.ai.personal.hosted_notice"),
                              symbol: "info.circle", tint: .secondary)
            }
            credentialsControls
            Divider()
            modelControls
            advancedControls
            Divider()
            saveAndTestControls
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            draft = initialDraft
            provider = PersonalAIProvider.matching(draft)
            advancedExpanded = provider == .custom
        }
        .onChange(of: draft) { previous, current in
            invalidateTest(); issue = nil
            let destinationChanged = previous.service != current.service || previous.baseURL != current.baseURL
            invalidateCatalog(clearList: destinationChanged)
            if destinationChanged {
                key = ""
                if provider != .custom { provider = PersonalAIProvider.matching(current) }
            }
        }
        .onChange(of: key) { invalidateTest(); invalidateCatalog(clearList: true); issue = nil }
        .onChange(of: models.version(.deep)) { invalidateTest() }
        .onChange(of: models.revision) { invalidateTest(); invalidateCatalog(clearList: true) }
        .onDisappear { invalidateTest(); invalidateCatalog(clearList: true); key = "" }
    }

    private var credentialsControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("settings.ai.personal.provider")
                Picker(L10n.text("settings.ai.personal.provider"), selection: Binding(
                    get: { provider }, set: { selectProvider($0) })) {
                    ForEach(PersonalAIProvider.allCases, id: \.self) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(L10n.text("settings.ai.personal.help"))
                .accessibilityIdentifier("personal-ai-provider")
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("API Key").font(.callout.weight(.medium))
                    Spacer(minLength: 12)
                    if let url = provider.keyURL {
                        Link(destination: url) {
                            Label(L10n.text("settings.ai.personal.get_key"), systemImage: "arrow.up.right")
                                .font(.caption)
                        }
                    }
                }
                SecureField("API Key", text: $key,
                            prompt: Text(L10n.text(models.canReusePersonalKey(for: draft)
                                ? "settings.ai.personal.key_saved" : "settings.ai.personal.key_enter")))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("personal-ai-key")
            }
        }
    }

    private var modelControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                fieldLabel("settings.ai.personal.model_label")
                Spacer(minLength: 12)
                if loadingModels {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel(L10n.text("settings.ai.catalog.loading"))
                    Button(L10n.text("common.cancel")) { invalidateCatalog(clearList: false) }
                        .buttonStyle(.link)
                } else {
                    Button { loadModels() } label: {
                        Label(L10n.text(catalog == nil ? "settings.ai.catalog.load" : "settings.ai.catalog.refresh"),
                              systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.link)
                    .disabled(draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .font(.caption)
            modelField
            if let catalog, !catalog.models.isEmpty {
                Button(L10n.text(manualModel ? "settings.ai.personal.choose_from_list" : "settings.ai.personal.manual")) {
                    manualModel.toggle()
                }
                .buttonStyle(.link)
                .font(.caption)
            } else if catalog == nil {
                Text(L10n.text("settings.ai.catalog.input_hint"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let destination = try? draft.normalizedDestination() {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("settings.ai.catalog.sharing"))
                    Text(verbatim: destination.baseURL + "/models")
                        .textSelection(.enabled)
                }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            catalogFeedback
        }
    }

    @ViewBuilder
    private var modelField: some View {
        if !manualModel, let catalog, !catalog.models.isEmpty {
            Picker(L10n.text("settings.ai.personal.model"), selection: $draft.model) {
                Text(L10n.text("settings.ai.personal.choose_model")).tag("")
                if !draft.model.isEmpty, !catalog.models.contains(where: { $0.id == draft.model }) {
                    Text(verbatim: draft.model).tag(draft.model)
                }
                ForEach(catalog.models) { model in
                    Text(verbatim: model.title).tag(model.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("personal-ai-model-list")
        } else {
            TextField(L10n.text("settings.ai.personal.model"), text: $draft.model,
                      prompt: Text(L10n.text("settings.ai.personal.model_placeholder")))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .autocorrectionDisabled()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("personal-ai-model")
        }
    }

    @ViewBuilder
    private var catalogFeedback: some View {
        if let catalogIssue {
            statusMessage(catalogIssue, symbol: "exclamationmark.circle", tint: .red)
        } else if let catalog, !loadingModels {
            VStack(alignment: .leading, spacing: 6) {
                Label(catalog.models.isEmpty ? L10n.text("settings.ai.catalog.empty")
                    : L10n.text("settings.ai.catalog.loaded", catalog.models.count),
                      systemImage: "list.bullet")
                if catalog.isPartial { Text(L10n.text("settings.ai.catalog.partial")) }
            }
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var advancedControls: some View {
        DisclosureGroup(isExpanded: $advancedExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("settings.ai.personal.url")
                    TextField(L10n.text("settings.ai.personal.url"), text: $draft.baseURL,
                              prompt: Text("https://api.example.com/v1"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .autocorrectionDisabled()
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("personal-ai-url")
                    Text(L10n.text("settings.ai.personal.url_help"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("settings.ai.personal.service")
                    Picker(L10n.text("settings.ai.personal.service"), selection: $draft.service) {
                        ForEach(PersonalModelConfiguration.Service.allCases, id: \.self) { service in
                            Text(service.title).tag(service)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 12)
        } label: {
            Text(L10n.text("settings.ai.personal.advanced")).foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private var saveAndTestControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let issue = issue ?? models.bindingIssue {
                statusMessage(issue, symbol: "exclamationmark.circle", tint: .red)
            }
            if let testMessage {
                statusMessage(testMessage, symbol: testFailed ? "exclamationmark.circle" : "checkmark.circle",
                              tint: testFailed ? .red : .green)
            }
            if models.isTextReady(.deep) {
                Text(L10n.text("settings.ai.personal.test_target", testProvider, testModel))
                    .font(.caption.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L10n.text(models.hasActivationCode
                ? "settings.ai.personal.test_hosted_compact" : "settings.ai.personal.privacy_compact"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if edited {
                Label(L10n.text("settings.ai.personal.unsaved"), systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if models.hasPersonalKey {
                    Button(L10n.text("settings.key.remove"), role: .destructive) {
                        invalidateTest(); invalidateCatalog(clearList: true)
                        do { try models.removePersonalKey(); key = ""; issue = nil }
                        catch { issue = error.localizedDescription }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(testing)
                }
                Spacer(minLength: 12)
                Button(L10n.text(testing ? "settings.connection.testing" : (models.hasActivationCode
                    ? "settings.ai.personal.test_jotway" : "settings.ai.personal.test_generation"))) { test() }
                    .buttonStyle(.bordered)
                    .disabled(testing || edited || !models.isTextReady(.deep))
                Button(L10n.text("settings.ai.personal.save_changes")) { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!edited || testing)
            }
            .controlSize(.large)
        }
    }

    private func fieldLabel(_ key: String) -> some View {
        Text(L10n.text(key)).font(.callout.weight(.medium))
    }

    private func statusMessage(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func selectProvider(_ next: PersonalAIProvider) {
        guard provider != next else { return }
        provider = next
        invalidateTest(); invalidateCatalog(clearList: true); issue = nil
        key = ""
        if next == .custom {
            advancedExpanded = true
        } else {
            draft.service = next.service
            draft.baseURL = next.baseURL
            draft.model = ""
            advancedExpanded = false
        }
        manualModel = true
    }

    private func invalidateTest() {
        testTask?.cancel(); testTask = nil; testID = nil; testMessage = nil; testFailed = false
    }

    private func invalidateCatalog(clearList: Bool) {
        catalogTask?.cancel(); catalogTask = nil; catalogID = nil; catalogIssue = nil
        if clearList { catalog = nil }
    }

    private func save() {
        invalidateTest(); invalidateCatalog(clearList: true); issue = nil
        do {
            try models.savePersonalModel(draft, key: key)
            draft = models.personalModel ?? draft; key = ""
            provider = PersonalAIProvider.matching(draft)
        } catch { issue = error.localizedDescription }
    }

    private func loadModels() {
        invalidateCatalog(clearList: false)
        do {
            let configuration = try draft.normalizedDestination()
            let credential = try models.personalKey(for: configuration, enteredKey: key)
            let id = UUID(), revision = models.revision, originalDraft = draft, originalKey = key
            catalogID = id
            catalogTask = Task { @MainActor in
                do {
                    let result = try await PersonalModelCatalog.load(configuration: configuration, key: credential)
                    guard !Task.isCancelled, catalogID == id, models.revision == revision,
                          draft == originalDraft, key == originalKey else { return }
                    catalog = result
                    if !result.models.isEmpty { manualModel = false }
                } catch {
                    guard !Task.isCancelled, catalogID == id, models.revision == revision,
                          draft == originalDraft, key == originalKey else { return }
                    catalogIssue = error.localizedDescription
                }
                catalogID = nil; catalogTask = nil
            }
        } catch { catalogIssue = error.localizedDescription }
    }

    private func test() {
        invalidateTest(); issue = nil
        let invocation: ModelTextInvocation
        do { invocation = try models.text(.deep) }
        catch { testMessage = error.localizedDescription; testFailed = true; return }
        let id = UUID(), version = models.version(.deep), revision = models.revision
        let provider = testProvider, model = testModel, originalDraft = draft, originalKey = key
        testID = id
        testTask = Task { @MainActor in
            let result: String, failed: Bool
            do {
                try Task.checkCancellation()
                var request = invocation.request("Reply with OK.", "This is a connection test. Reply briefly.")
                request.maximumTokens = 128; request.maximumTokensForThinkingModel = 16_384; request.timeout = 30
                _ = try await invocation.call(request, loggingPurpose: .connectionTest)
                result = L10n.text("settings.ai.personal.generation_ok", provider, model); failed = false
            } catch { result = error.localizedDescription; failed = true }
            guard !Task.isCancelled, testID == id, version == models.version(.deep), revision == models.revision,
                  draft == originalDraft, key == originalKey else { return }
            testMessage = result; testFailed = failed; testID = nil; testTask = nil
        }
    }
}
