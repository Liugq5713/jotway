import Foundation

/// Kimi（Moonshot）是 `OpenAICompatible` 的薄配置，无服务商专有请求字段。
enum Moonshot {
    static func source() -> AIProviderPlugin.Source {
        OpenAICompatible.source(.init(
            id: "moonshot", title: "Kimi", brand: "Kimi", providerKey: .moonshot,
            baseURL: URL(string: "https://api.moonshot.cn/v1/chat/completions")!,
            modelID: "kimi-k2-0905-preview", displayPrefix: "moonshot",
            keyURL: URL(string: "https://platform.moonshot.cn/console/api-keys")!,
            detail: "Model: kimi-k2. Record text and related context are sent to Kimi (Moonshot); charges are billed to your Moonshot account."))
    }
}
