import Foundation
import Observation

@MainActor @Observable
final class ModelConfiguration {
    enum Capability: String, CaseIterable, Codable, Sendable { case fast, deep, embedding }
    let preferences: UserDefaults
    let keys: APIKeyStore
    var sources: [AIProviderPlugin.Source]
    let fastSource: AIProviderPlugin.Source
    private var embeddingBindingRevision = 0
    private(set) var embeddingProfile = NotesEmbeddingProfile()
    let embeddingTransport: NotesEmbeddingClient.Transport
    private(set) var embeddingFactory: (@MainActor (@escaping @Sendable () async throws -> Void) throws -> ModelEmbeddingInvocation)?
    struct TextModel: Codable, Equatable, Hashable, Sendable {
        let source: String
        var model: String? = nil
    }
    struct TextBinding: Codable, Equatable, Sendable {
        var primary: TextModel
        var fallback: TextModel?
    }
    struct TextBindings: Codable, Sendable {
        var fast: TextBinding
        var deep: TextBinding
    }
    static let bindingsKey = "plugin.ai.textBindings.v1"
    static let embeddingEndpointKey = "plugin.ai.embeddingEndpoint.v1"
    private(set) var bindings: TextBindings
    private(set) var bindingIssue: String?
    private let usesInjectedFast: Bool
    var deepSelection: String { bindings.deep.primary.source }
    private(set) var revision = 0
    private var credentialVersions: [APIKeyStore.Provider: Int] = [:]

    init(preferences: UserDefaults, keys: APIKeyStore = .shared,
         sources: [AIProviderPlugin.Source]? = nil, fastSource: AIProviderPlugin.Source? = nil,
         embeddingTransport: @escaping NotesEmbeddingClient.Transport = NotesEmbeddingClient.send) {
        self.preferences = preferences; self.keys = keys
        self.embeddingTransport = embeddingTransport
        let registered = sources ?? bundledAISources(keys: keys)
        self.sources = registered
        self.fastSource = fastSource ?? DeepSeek.fastSource(readKey: { try keys.load(for: .deepSeek) })
        usesInjectedFast = fastSource != nil
        let selected = preferences.string(forKey: "plugin.ai.source") ?? "deepSeek"
        let selectedSource = registered.first { $0.id == selected }
        let modelKey = selectedSource?.modelPreferenceKey ?? "plugin.ai.\(selected)Model"
        let selectedModel = preferences.string(forKey: modelKey) ?? selectedSource?.models.first?.id
        bindings = .init(fast: .init(primary: .init(source: self.fastSource.id),
                                    fallback: fastSource == nil ? .init(source: "moonshot") : nil),
                         deep: .init(primary: .init(source: selected, model: selectedModel),
                                     fallback: selected == "deepSeek" ? .init(source: "moonshot")
                                        : selected == "moonshot" ? .init(source: "deepSeek") : nil))
        if preferences.object(forKey: Self.bindingsKey) != nil {
            if let data = preferences.data(forKey: Self.bindingsKey),
               let saved = try? JSONDecoder().decode(TextBindings.self, from: data),
               saved.fast.primary != saved.fast.fallback, saved.deep.primary != saved.deep.fallback {
                bindings = saved
            } else { bindingIssue = L10n.text("settings.ai.binding_invalid") }
        } else if let data = try? JSONEncoder().encode(bindings) {
            preferences.set(data, forKey: Self.bindingsKey)
        }
        embeddingProfile.endpoint = preferences.string(forKey: Self.embeddingEndpointKey) ?? ""
    }

    func bindEmbedding(profile: NotesEmbeddingProfile,
                       factory: @escaping @MainActor (@escaping @Sendable () async throws -> Void) throws -> ModelEmbeddingInvocation) {
        embeddingProfile = profile; embeddingFactory = factory; embeddingBindingRevision &+= 1; changed()
    }
    var embeddingAvailable: Bool {
        embeddingFactory != nil || (ModelEmbeddingSpace.validEndpoint(embeddingProfile.endpoint)
            && (try? loadKey(.notesEmbedding)) != nil)
    }
    func setEmbeddingEndpoint(_ value: String) throws {
        let endpoint = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard endpoint.isEmpty || ModelEmbeddingSpace.validEndpoint(endpoint) else { throw NotesHistoryError.configuration }
        guard endpoint != embeddingProfile.endpoint else { return }
        preferences.set(endpoint, forKey: Self.embeddingEndpointKey)
        embeddingProfile.endpoint = endpoint
        embeddingBindingRevision &+= 1
        changed()
    }
    var deepSource: AIProviderPlugin.Source? { sources.first { $0.id == deepSelection } }
    var deepModel: String? {
        bindings.deep.primary.model ?? deepSource.flatMap { source in
            source.modelPreferenceKey.flatMap { preferences.string(forKey: $0) } ?? source.models.first?.id
        }
    }
    func binding(_ capability: Capability) -> TextBinding { capability == .fast ? bindings.fast : bindings.deep }
    func textSources(_ capability: Capability) -> [AIProviderPlugin.Source] {
        capability == .fast ? (usesInjectedFast ? [fastSource] : [fastSource, Moonshot.fastSource(readKey: { [keys] in try keys.load(for: .moonshot) })]) : sources
    }
    func source(for model: TextModel, capability: Capability) -> AIProviderPlugin.Source? {
        textSources(capability).first { $0.id == model.source }
    }
    func choices(_ capability: Capability) -> [TextModel] {
        textSources(capability).flatMap { source in
            source.models.isEmpty ? [TextModel(source: source.id)] : source.models.map { TextModel(source: source.id, model: $0.id) }
        }
    }
    func title(_ model: TextModel, capability: Capability) -> String {
        guard let source = source(for: model, capability: capability) else { return model.source }
        return model.model.map { source.title + " · " + $0 } ?? source.title
    }
    @discardableResult
    func setBinding(_ binding: TextBinding, for capability: Capability) -> Bool {
        guard capability != .embedding, choices(capability).contains(binding.primary),
              binding.fallback == nil || (binding.fallback != binding.primary && choices(capability).contains(binding.fallback!)) else { return false }
        var next = bindings
        if capability == .fast { next.fast = binding } else { next.deep = binding }
        guard let data = try? JSONEncoder().encode(next) else { return false }
        preferences.set(data, forKey: Self.bindingsKey)
        bindings = next; bindingIssue = nil; changed()
        return true
    }
    func swap(_ capability: Capability) {
        let current = binding(capability)
        guard let fallback = current.fallback else { return }
        setBinding(.init(primary: fallback, fallback: current.primary), for: capability)
    }
    func selectDeep(_ id: String) {
        guard id != deepSelection else { return }
        var next = bindings.deep
        next.primary = .init(source: id)
        if next.fallback == next.primary { next.fallback = bindings.deep.primary }
        guard setBinding(next, for: .deep) else { return }
        preferences.set(id, forKey: "plugin.ai.source")
    }
    func selectDeepModel(_ id: String) {
        var next = bindings.deep; next.primary.model = id
        guard setBinding(next, for: .deep) else { return }
        if let key = deepSource?.modelPreferenceKey { preferences.set(id, forKey: key) }
    }
    private func changed() { revision &+= 1 }
    func version(_ capability: Capability) -> String {
        if capability == .embedding {
            return "\(embeddingProfile.identity)/\(embeddingBindingRevision)|\(credentialVersion(.notesEmbedding))"
        }
        func version(_ model: TextModel) -> String {
            let source = source(for: model, capability: capability)
            let provider: APIKeyStore.Provider? = model.source == "moonshot" ? .moonshot : model.source == "deepSeek" ? .deepSeek : nil
            return "\(model.source)/\(model.model ?? "")/\(source?.version(model.model) ?? "unavailable")|\(provider.map { credentialVersion($0) } ?? 0)"
        }
        let chain = binding(capability)
        return "text-v1|\(bindingIssue ?? "")|\(version(chain.primary))|\(chain.fallback.map(version) ?? "none")"
    }
    func loadKey(_ provider: APIKeyStore.Provider) throws -> String? { try keys.load(for: provider) }
    func saveKey(_ key: String, for provider: APIKeyStore.Provider) throws {
        try keys.save(key.trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
        advanceCredentialVersion(provider); changed()
    }
    func removeKey(for provider: APIKeyStore.Provider) throws {
        try keys.remove(for: provider)
        advanceCredentialVersion(provider); changed()
    }
    private func credentialVersion(_ provider: APIKeyStore.Provider) -> Int {
        credentialVersions[provider] ?? preferences.integer(forKey: "model.credentialRevision." + provider.rawValue)
    }
    private func advanceCredentialVersion(_ provider: APIKeyStore.Provider) {
        let version = credentialVersion(provider) &+ 1
        credentialVersions[provider] = version
        preferences.set(version, forKey: "model.credentialRevision." + provider.rawValue)
    }
    func configuration(_ model: TextModel, capability: Capability) throws -> AIProviderPlugin.Configuration {
        guard bindingIssue == nil else { throw AIProviderPlugin.Failure(message: bindingIssue!, runtimeLogCode: .configuration) }
        guard capability != .embedding, let selected = source(for: model, capability: capability) else {
            throw AIProviderPlugin.Failure(message: L10n.text("error.ai_source_unregistered", model.source), runtimeLogCode: .configuration)
        }
        let selectedModel = model.model ?? (capability == .deep && model == bindings.deep.primary ? deepModel : nil)
        if let selectedModel, !selected.models.contains(where: { $0.id == selectedModel }) {
            throw AIProviderPlugin.Failure(message: "Selected model is unavailable", runtimeLogCode: .configuration)
        }
        let result = try selected.configure(selectedModel)
        return .init(version: version(capability), modelID: result.modelID, providerID: result.providerID, perform: result.perform)
    }
    func textConfiguration(_ capability: Capability) throws -> AIProviderPlugin.Configuration {
        try configuration(binding(capability).primary, capability: capability)
    }
    struct Snapshot: Sendable {
        let text: [Capability: ModelTextInvocation]
        let embedding: ModelEmbeddingInvocation?
    }
    func snapshot(for capabilities: Set<Capability>,
                  validate: @escaping @Sendable () async throws -> Void = { try Task.checkCancellation() }) throws -> Snapshot {
        var text: [Capability: ModelTextInvocation] = [:]
        for capability in capabilities where capability == .fast || capability == .deep {
            text[capability] = try self.text(capability, validate: validate)
        }
        return .init(text: text, embedding: capabilities.contains(.embedding) ? try embedding(validate: validate) : nil)
    }
    func text(_ capability: Capability,
              validate: @escaping @Sendable () async throws -> Void = { try Task.checkCancellation() }) throws -> ModelTextInvocation {
        let primary = try ModelTextInvocation.direct(textConfiguration(capability), validate: validate)
        let fallback = binding(capability).fallback.flatMap { model in
            try? ModelTextInvocation.direct(configuration(model, capability: capability), validate: validate)
        }
        return ModelTextInvocation.fallback(primary: primary, fallback: fallback,
            capability: capability, version: version(capability),
            fallbackUnavailable: binding(capability).fallback != nil && fallback == nil, validate: validate)
    }
}

extension ModelConfiguration {
    func saveSourceKey(_ key: String, source: AIProviderPlugin.Source) throws {
        if source.id == "deepSeek" { try saveKey(key, for: .deepSeek) }
        else if source.id == "moonshot" { try saveKey(key, for: .moonshot) }
        else {
            guard let save = source.saveKey else { throw APIKeyStore.Failure.inaccessible }
            try save(key); revision &+= 1
        }
    }
    func removeSourceKey(_ source: AIProviderPlugin.Source) throws {
        if source.id == "deepSeek" { try removeKey(for: .deepSeek) }
        else if source.id == "moonshot" { try removeKey(for: .moonshot) }
        else {
            guard let remove = source.removeKey else { throw APIKeyStore.Failure.inaccessible }
            try remove(); revision &+= 1
        }
    }
}

extension ModelConfiguration {
    struct Status: Identifiable {
        let id: Capability
        let title: String
        let detail: String
        let ready: Bool
    }
    var statuses: [Status] {
        Capability.allCases.map { capability in
            switch capability {
            case .fast, .deep:
                let chain = binding(capability)
                let title = title(chain.primary, capability: capability)
                return .init(id: capability, title: title, detail: bindingIssue ?? source(for: chain.primary, capability: capability)?.detail ?? "Saved model is unavailable.",
                    ready: (try? textConfiguration(capability)) != nil)
            case .embedding: return .init(id: capability, title: embeddingProfile.model,
                detail: "Notes text is sent to the configured embedding service; its account is billed.", ready: embeddingAvailable)
            }
        }
    }
}
