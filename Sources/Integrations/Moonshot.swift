import Foundation

/// Fixed official Kimi Code services; thinking uses the caller's separate total budget.
enum Moonshot {
    static let modelID = "kimi-k2.7-code"
    static let fastModelID = "kimi-k2.7-code-highspeed"
    static func source(readKey: (@MainActor @Sendable () throws -> String?)? = nil) -> AIProviderPlugin.Source {
        source(model: modelID, title: "Kimi Code", readKey: readKey)
    }
    static func fastSource(readKey: (@MainActor @Sendable () throws -> String?)? = nil) -> AIProviderPlugin.Source {
        source(model: fastModelID, title: "Kimi Code Highspeed", readKey: readKey)
    }
    private static func source(model: String, title: String,
                               readKey: (@MainActor @Sendable () throws -> String?)?) -> AIProviderPlugin.Source {
        OpenAICompatible.source(.init(
            id: "moonshot", title: title, brand: "Kimi", providerKey: .moonshot,
            baseURL: URL(string: "https://api.moonshot.cn/v1/chat/completions")!,
            modelID: model, displayPrefix: "moonshot",
            keyURL: URL(string: "https://platform.moonshot.cn/console/api-keys")!,
            detail: "Thinking and output share the token budget. Input is sent to Moonshot and billed to your Moonshot account.",
            thinking: true), readKey: readKey)
    }
}
