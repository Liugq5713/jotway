/// Existing preference ID; a missing registration never replaces the saved selection.
let defaultAISourceID = "deepSeek"

func bundledAISources() -> [AIProviderPlugin.Source] {
    // DeepSeek 与 Kimi 走进程内 HTTP，所有构建都提供。
    // 数组顺序即设置页展示顺序。
    [DeepSeek.source(), Moonshot.source()]
}

/// 插件的显式安装入口。应用主体只调用这个函数。
///
/// 所有构建都装配 AI Provider 和设置页的连接测试。
@MainActor
func installPlugins(into app: AppState) {
    let provider = AIProviderPlugin(configuration: { [weak app] in
        guard let app else { throw AIProviderPlugin.Failure(message: L10n.text("settings.ai.configuration_unavailable")) }
        return try app.aiRequestConfiguration()
    }, manualConfiguration: { [weak app] in app?.aiManualConfiguration ?? .init() })
    app.onTestAIConnection = {
        let log = RuntimeLog.Context(purpose: .connectionTest)
        _ = try await RuntimeLog.$current.withValue(log) {
            try await provider.generate(content: "Jotway connection test.",
                                        instructions: "Reply with JOTWAY_CONNECTION_OK only.")
        }
    }
}
