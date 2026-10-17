import Foundation

/// DeepSeek 是 `OpenAICompatible` 的薄配置；专有的 `thinking` 参数经 `extraBody` 传入。
enum DeepSeek {
    static let modelID = "deepseek-v4-pro"
    static let qualifiedModelID = "deepseek/\(modelID)"
    static let planningModelID = "deepseek-flash"

    static func fastSource(readKey: @escaping @MainActor @Sendable () throws -> String? = loadAPIKey,
                               session: URLSession? = nil) -> AIProviderPlugin.Source {
        OpenAICompatible.source(.init(
            id: "deepSeek", title: "DeepSeek Flash", brand: "DeepSeek", providerKey: .deepSeek,
            baseURL: URL(string: "https://api.deepseek.com/chat/completions")!,
            modelID: planningModelID, displayPrefix: "deepseek",
            keyURL: URL(string: "https://platform.deepseek.com/api_keys")!,
            detail: "Fast text generation with DeepSeek Flash. Input is sent to DeepSeek and billed to your DeepSeek account.",
            extraBody: ["thinking": ["type": "disabled"]]), readKey: readKey, session: session)
    }

    static func source(readKey: @escaping @MainActor @Sendable () throws -> String? = loadAPIKey,
                       session suppliedSession: URLSession? = nil) -> AIProviderPlugin.Source {
        OpenAICompatible.source(.init(
            id: "deepSeek", title: "DeepSeek", brand: "DeepSeek", providerKey: .deepSeek,
            baseURL: URL(string: "https://api.deepseek.com/chat/completions")!,
            modelID: modelID, displayPrefix: "deepseek",
            keyURL: URL(string: "https://platform.deepseek.com/api_keys")!,
            detail: "Model: \(modelID). Record text and related context are sent to DeepSeek; charges are billed to your DeepSeek account.",
            extraBody: ["thinking": ["type": "disabled"]]),
            readKey: readKey, session: suppliedSession)
    }

    @MainActor
    static func loadAPIKey() throws -> String? {
        try APIKeyStore.shared.load(for: .deepSeek)
    }
}
