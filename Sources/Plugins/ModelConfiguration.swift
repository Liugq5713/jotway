import Foundation
import Observation

@MainActor @Observable
final class ModelConfiguration {
    enum Capability: String, CaseIterable, Codable, Sendable { case fast, deep }
    let preferences: UserDefaults
    let keys: APIKeyStore
    var sources: [AIProviderPlugin.Source]
    private let injectedFast: AIProviderPlugin.Source?
    struct TextModel: Codable, Equatable, Hashable, Sendable {
        let source: String
        var model: String? = nil
    }
    // Read-only legacy schema for migration. Fallbacks are never executed.
    struct TextBinding: Codable, Equatable, Sendable {
        var primary: TextModel
        var fallback: TextModel?
    }
    struct TextBindings: Codable, Sendable {
        var fast: TextBinding
        var deep: TextBinding
    }
    static let bindingsKey = "plugin.ai.textBindings.v1"
    private(set) var personalModel: PersonalModelConfiguration?
    private(set) var bindingIssue: String?
    private var legacySelection: TextModel
    private(set) var revision = 0
    let hostedAI: HostedAIState
    var hostedAccount: HostedAI.Account? { hostedAI.account }
    private var credentialVersions: [APIKeyStore.Provider: Int] = [:]

    init(preferences: UserDefaults, keys: APIKeyStore = .shared,
         sources: [AIProviderPlugin.Source]? = nil, fastSource: AIProviderPlugin.Source? = nil,
         hostedAI: HostedAIState? = nil) {
        self.preferences = preferences; self.keys = keys
        self.hostedAI = hostedAI ?? HostedAIState()
        let availableSources = sources ?? bundledAISources(keys: keys)
        self.sources = availableSources
        injectedFast = fastSource
        let selected = preferences.string(forKey: "plugin.ai.source") ?? "personal"
        let registered = availableSources.first { $0.id == selected }
        legacySelection = .init(source: selected,
            model: preferences.string(forKey: registered?.modelPreferenceKey ?? "plugin.ai.\(selected)Model"))
        if preferences.object(forKey: PersonalModelConfiguration.preferenceKey) != nil {
            if let data = preferences.data(forKey: PersonalModelConfiguration.preferenceKey),
               let saved = try? JSONDecoder().decode(PersonalModelConfiguration.self, from: data),
               let valid = try? saved.normalized() { personalModel = valid }
            else { bindingIssue = L10n.text("settings.ai.binding_invalid") }
        } else {
            if preferences.object(forKey: Self.bindingsKey) != nil {
                if let data = preferences.data(forKey: Self.bindingsKey),
                   let saved = try? JSONDecoder().decode(TextBindings.self, from: data) {
                    legacySelection = saved.deep.primary
                    // Old activation overwrote both bindings. Recover only a known saved personal choice.
                    if legacySelection.source == HostedAI.sourceID {
                        if ["deepSeek", "moonshot"].contains(selected) { legacySelection = .init(source: selected) }
                        else if (try? keys.load(for: .deepSeek)) != nil { legacySelection = .init(source: "deepSeek") }
                        else if (try? keys.load(for: .moonshot)) != nil { legacySelection = .init(source: "moonshot") }
                        else { legacySelection = .init(source: "personal") }
                    }
                } else { bindingIssue = L10n.text("settings.ai.binding_invalid") }
            }
            if bindingIssue == nil {
                if legacySelection.source == "deepSeek" {
                    personalModel = .init(baseURL: "https://api.deepseek.com", model: legacySelection.model ?? DeepSeek.modelID, credential: .deepSeek)
                } else if legacySelection.source == "moonshot" {
                    personalModel = .init(baseURL: "https://api.moonshot.cn/v1", model: legacySelection.model ?? Moonshot.modelID, credential: .moonshot)
                }
                if let personalModel, let data = try? JSONEncoder().encode(personalModel) {
                    preferences.set(data, forKey: PersonalModelConfiguration.preferenceKey)
                }
            }
        }
    }

    var hasActivationCode: Bool { hostedAI.hasCode }
    var hasPersonalKey: Bool { (try? keys.load(for: personalModel?.credential ?? .personalAI)) != nil }
    var deepSelection: String { binding(.deep).primary.source }
    var deepSource: AIProviderPlugin.Source? { source(for: binding(.deep).primary, capability: .deep) }
    var deepModel: String? {
        binding(.deep).primary.model ?? deepSource.flatMap { source in
            source.modelPreferenceKey.flatMap { preferences.string(forKey: $0) } ?? source.models.first?.id
        }
    }

    /// Route before choosing a model. Code presence, including an unreadable code, wins over personal settings.
    func binding(_ capability: Capability) -> TextBinding {
        if hasActivationCode {
            return .init(primary: .init(source: HostedAI.sourceID,
                model: capability == .fast ? HostedAI.fastModel : HostedAI.deepModel))
        }
        if let personalModel { return .init(primary: .init(source: "personal", model: personalModel.model)) }
        if capability == .fast, let injectedFast { return .init(primary: .init(source: injectedFast.id)) }
        return .init(primary: legacySelection)
    }
    func source(for model: TextModel, capability: Capability) -> AIProviderPlugin.Source? {
        if model.source == HostedAI.sourceID { return HostedAI.source() }
        if model.source == "personal", let personalModel { return try? personalModel.source(keys: keys) }
        if capability == .fast, let injectedFast, injectedFast.id == model.source { return injectedFast }
        return sources.first { $0.id == model.source }
    }

    func savePersonalModel(_ proposed: PersonalModelConfiguration, key rawKey: String) throws {
        var next = try proposed.normalized()
        let key = try personalKey(for: next, enteredKey: rawKey)
        next.credential = .personalAI
        let data = try JSONEncoder().encode(next)
        try keys.save(key, for: .personalAI)
        preferences.set(data, forKey: PersonalModelConfiguration.preferenceKey)
        personalModel = next; bindingIssue = nil
        advanceCredentialVersion(.personalAI); changed()
    }

    func canReusePersonalKey(for proposed: PersonalModelConfiguration) -> Bool {
        guard let next = try? proposed.normalizedDestination(), let current = personalModel else { return false }
        return current.baseURL == next.baseURL && current.service == next.service && hasPersonalKey
    }

    /// Shared by saving and explicit discovery. Never forward a saved key to a new destination.
    func personalKey(for proposed: PersonalModelConfiguration, enteredKey rawKey: String) throws -> String {
        let next = try proposed.normalizedDestination()
        let entered = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !entered.isEmpty { return try OpenAICompatible.validatedKey(entered, brand: "AI") }
        guard let current = personalModel, current.baseURL == next.baseURL, current.service == next.service,
              let saved = try keys.load(for: current.credential) else {
            throw AIProviderPlugin.Failure(message: L10n.text("settings.ai.personal.key_required"), runtimeLogCode: .configuration)
        }
        return try OpenAICompatible.validatedKey(saved, brand: "AI")
    }
    func removePersonalKey() throws {
        try removeKey(for: personalModel?.credential ?? .personalAI)
    }
    func activateHostedAI(_ code: String) async throws {
        let revision = try await hostedAI.activate(code)
        guard revision == hostedAI.credentialRevision else { throw CancellationError() }
        changed()
    }
    func refreshHostedAccount() async { await hostedAI.refresh() }
    func removeActivationCode() throws { try hostedAI.remove(); changed() }
    private func changed() { revision &+= 1 }

    func version(_ capability: Capability) -> String {
        if hasActivationCode {
            return "hosted|\(capability.rawValue)|\(binding(capability).primary.model ?? "")|\(hostedAI.credentialRevision)"
        }
        if let personalModel {
            return "personal|\(bindingIssue ?? "")|\(personalModel.identity)|\(credentialVersion(personalModel.credential))"
        }
        let model = binding(capability).primary
        return "single|\(bindingIssue ?? "")|\(model.source)|\(source(for: model, capability: capability)?.version(model.model) ?? "unavailable")"
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
        if hasActivationCode {
            guard let code = try hostedAI.loadCode() else { throw HostedAI.failure(status: 401) }
            let modelID = capability == .fast ? HostedAI.fastModel : HostedAI.deepModel
            let result = try HostedAI.adapter(model: modelID, readCode: { code }).configure(nil)
            let state = hostedAI, credentialRevision = state.credentialRevision
            return .init(version: version(capability), modelID: result.modelID, providerID: result.providerID) { request in
                do {
                    let response = try await result.perform(request)
                    await state.finishedCall(credentialRevision: credentialRevision, problem: nil)
                    return response
                } catch {
                    await state.finishedCall(credentialRevision: credentialRevision, problem: HostedAI.problem(error))
                    throw error
                }
            }
        }
        guard bindingIssue == nil else { throw AIProviderPlugin.Failure(message: bindingIssue!, runtimeLogCode: .configuration) }
        // Personal selection is also centralized; old callers cannot opt into another provider.
        let selected: AIProviderPlugin.Source
        let selectedModel: String?
        if let personalModel {
            selected = try personalModel.source(keys: keys); selectedModel = nil
        } else {
            guard model.source != HostedAI.sourceID, let source = source(for: model, capability: capability) else {
                throw AIProviderPlugin.Failure(message: L10n.text("settings.ai.personal.required"), runtimeLogCode: .configuration)
            }
            selected = source; selectedModel = model.model
            if let selectedModel, !selected.models.contains(where: { $0.id == selectedModel }) {
                throw AIProviderPlugin.Failure(message: L10n.text("settings.ai.personal.invalid"), runtimeLogCode: .configuration)
            }
        }
        let result = try selected.configure(selectedModel)
        return .init(version: version(capability), modelID: result.modelID, providerID: result.providerID, perform: result.perform)
    }
    func isTextReady(_ capability: Capability) -> Bool {
        _ = revision
        return (try? textConfiguration(capability)) != nil
    }
    func textConfiguration(_ capability: Capability) throws -> AIProviderPlugin.Configuration {
        try configuration(binding(capability).primary, capability: capability)
    }
    struct Snapshot: Sendable {
        let text: [Capability: ModelTextInvocation]
    }
    func snapshot(for capabilities: Set<Capability>,
                  validate: @escaping @Sendable () async throws -> Void = { try Task.checkCancellation() }) throws -> Snapshot {
        var text: [Capability: ModelTextInvocation] = [:]
        for capability in capabilities {
            text[capability] = try self.text(capability, validate: validate)
        }
        return .init(text: text)
    }
    func text(_ capability: Capability,
              validate: @escaping @Sendable () async throws -> Void = { try Task.checkCancellation() }) throws -> ModelTextInvocation {
        let direct = try ModelTextInvocation.direct(textConfiguration(capability), validate: validate)
        var invocation = ModelTextInvocation.bounded(direct, capability: capability, validate: validate)
        invocation.allowsAutomaticRetry = !hasActivationCode
        return invocation
    }

    struct Status: Identifiable {
        let id: Capability
        let title: String
        let detail: String
        let ready: Bool
    }
    var statuses: [Status] {
        Capability.allCases.map { capability in
            let model = binding(capability).primary
            return .init(id: capability, title: hasActivationCode ? "Jotway AI" : personalModel?.model ?? model.source,
                detail: bindingIssue ?? L10n.text("settings.ai.personal.privacy"), ready: isTextReady(capability))
        }
    }
}
