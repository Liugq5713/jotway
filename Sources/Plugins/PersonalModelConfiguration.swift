import Foundation

/// One personal text model. Secrets are stored separately from these preferences.
struct PersonalModelConfiguration: Codable, Equatable, Sendable {
    enum Service: String, Codable, CaseIterable, Sendable {
        case openAICompatible, claude
        var title: String { self == .claude ? "Claude (Anthropic)" : L10n.text("settings.ai.personal.openai") }
        var defaultBaseURL: String { self == .claude ? "https://api.anthropic.com/v1" : "" }
    }
    static let preferenceKey = "plugin.ai.personalModel.v1"
    var service: Service = .openAICompatible
    var baseURL = ""
    var model = ""
    // A migrated choice may continue using its existing credential until explicitly saved.
    var credential: APIKeyStore.Provider = .personalAI

    func normalized() throws -> Self {
        var value = self
        value.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.baseURL.hasSuffix("/") { value.baseURL.removeLast() }
        value.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.model.isEmpty, value.model.utf8.count <= 256,
              value.model.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              [.personalAI, .deepSeek, .moonshot].contains(value.credential),
              let url = URLComponents(string: value.baseURL), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.url != nil else {
            throw AIProviderPlugin.Failure(message: L10n.text("settings.ai.personal.invalid"), runtimeLogCode: .configuration)
        }
        return value
    }

    var endpoint: URL {
        URL(string: baseURL)!.appendingPathComponent(service == .claude ? "messages" : "chat/completions")
    }
    var identity: String { "\(service.rawValue)|\(baseURL)|\(model)|\(credential.rawValue)" }

    @MainActor
    func source(keys: APIKeyStore) throws -> AIProviderPlugin.Source {
        let value = try normalized()
        let readKey: @MainActor @Sendable () throws -> String? = { try keys.load(for: value.credential) }
        if value.service == .claude {
            return Claude.source(endpoint: value.endpoint, model: value.model, readKey: readKey)
        }
        // Preserve the known vendors' token semantics without applying their fields to other hosts.
        let deepSeek = value.endpoint.host == "api.deepseek.com"
        let kimiCode = value.endpoint.host == "api.moonshot.cn" && value.model.hasPrefix("kimi-k2.7-code")
        return OpenAICompatible.source(.init(id: "personal", title: value.model, brand: "AI",
            providerKey: value.credential, baseURL: value.endpoint, modelID: value.model,
            displayPrefix: "personal", keyURL: URL(string: value.baseURL)!,
            detail: L10n.text("settings.ai.personal.privacy"),
            extraBody: deepSeek ? ["thinking": ["type": "disabled"]] : [:], thinking: kimiCode,
            exactModel: false, jsonMode: deepSeek || kimiCode), readKey: readKey)
    }
}
