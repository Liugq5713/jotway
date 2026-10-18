/// Existing preference ID; a missing registration never replaces the saved selection.
let defaultAISourceID = "deepSeek"

@MainActor
func bundledAISources(keys: APIKeyStore = .shared) -> [AIProviderPlugin.Source] {
    // DeepSeek 与 Kimi 走进程内 HTTP，所有构建都提供。
    // 数组顺序即设置页展示顺序。
    [HostedAI.source(), DeepSeek.source(readKey: { try keys.load(for: .deepSeek) }),
     Moonshot.source(readKey: { try keys.load(for: .moonshot) })]
}

/// 插件的显式安装入口。应用主体只调用这个函数。
///
/// 所有构建都装配 AI Provider 和设置页的连接测试。
@MainActor
func installPlugins(into app: AppState) {
    app.onTestAIConnection = { [weak app] in
        guard let app else { throw CancellationError() }
        let invocation = try app.models.text(.deep)
        let instructions = WritingPreferences.instructions("Reply with JOTWAY_CONNECTION_OK only.", configuration: app.aiManualConfiguration)
        _ = try await invocation("Jotway connection test.", instructions, loggingPurpose: .connectionTest)
    }
}
