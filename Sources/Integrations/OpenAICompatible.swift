import Foundation

/// OpenAI 兼容 chat/completions 来源的共享工厂。各家只提供编译期固定参数，
/// 网络、错误分支与安全约束（无缓存会话、NoRedirect、响应上限与格式校验）全部收敛在此，
/// 新增一家只需写一个薄 `source()`，不复制这里的实现。
enum OpenAICompatible {
    /// 各服务商的编译期固定参数。初始化后只读，`extraBody` 仅允许不可变 JSON 值，故按 Sendable 使用。
    struct Spec: @unchecked Sendable {
        let id: String                    // Source.id，同时作为日志 providerID
        let title: String                 // 设置页显示名
        let brand: String                 // 错误文案品牌名
        let providerKey: APIKeyStore.Provider
        let baseURL: URL                  // 固定 chat/completions 地址，不接受用户输入
        let modelID: String               // 线上模型名
        let displayPrefix: String         // modelID/version 命名前缀
        let keyURL: URL                   // 申请 key 链接
        let detail: String                // 设置页说明
        var extraBody: [String: Any] = [:] // 服务商专有请求字段（如 DeepSeek 的 thinking）
        var maxTokens = 8192
    }

    static func source(_ spec: Spec,
                       readKey explicitReadKey: (@MainActor @Sendable () throws -> String?)? = nil,
                       session suppliedSession: URLSession? = nil) -> AIProviderPlugin.Source {
        let readKey: @MainActor @Sendable () throws -> String? = explicitReadKey ?? { try APIKeyStore.shared.load(for: spec.providerKey) }
        let network = URLSessionConfiguration.ephemeral
        network.timeoutIntervalForRequest = 120
        network.timeoutIntervalForResource = 120
        network.urlCache = nil
        network.httpCookieStorage = nil
        network.urlCredentialStorage = nil
        let session = suppliedSession ?? URLSession(configuration: network)
        let model = "\(spec.displayPrefix)/\(spec.modelID)"
        let version = "\(model)/v1"
        return .init(id: spec.id, title: spec.title,
            detail: spec.detail,
            keyURL: spec.keyURL,
            hasKey: { try APIKeyStore.shared.load(for: spec.providerKey) != nil },
            saveKey: { try APIKeyStore.shared.save(validatedKey($0, brand: spec.brand), for: spec.providerKey) },
            removeKey: { try APIKeyStore.shared.remove(for: spec.providerKey) },
            version: { _ in version }, configure: { _ in
                let key = try validatedKey(readKey(), brand: spec.brand)
                return .init(version: version, modelID: model, providerID: spec.id) { request in
                    try await generate(request, spec: spec, apiKey: key, session: session)
                }
            })
    }

    private static func generate(_ request: AIProviderPlugin.Request, spec: Spec, apiKey: String, session: URLSession) async throws -> AIProviderPlugin.Response {
        let model = "\(spec.displayPrefix)/\(spec.modelID)"
        var http = URLRequest(url: spec.baseURL)
        http.httpMethod = "POST"
        http.timeoutInterval = 120
        http.cachePolicy = .reloadIgnoringLocalCacheData
        http.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": spec.modelID, "stream": false,
            "max_tokens": spec.maxTokens,
            "messages": [["role": "system", "content": request.instructions],
                         ["role": "user", "content": request.content]]
        ]
        for (field, value) in spec.extraBody { body[field] = value }
        http.httpBody = try JSONSerialization.data(withJSONObject: body)
        let log = RuntimeLog.current
        let started = RuntimeLog.ticks()
        log?.emit(.stageStarted, .init(stage: .service, requestedModel: model))
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: http, delegate: NoRedirect())
        } catch {
            log?.failed(.service, error)
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if (error as? URLError)?.code == .timedOut {
                throw AIProviderPlugin.Failure(message: L10n.text("ai.error.timeout", spec.brand), runtimeLogCode: .timeout)
            }
            // 不把网络错误中的请求、认证头或服务端原始响应写入记录错误字段。
            throw AIProviderPlugin.Failure(message: L10n.text("ai.error.disconnected", spec.brand), runtimeLogCode: .disconnected)
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw AIProviderPlugin.Failure(message: L10n.text("ai.error.invalid_response", spec.brand))
        }
        log?.emit(.stageFinished, .init(stage: .service, outcome: (200...299).contains(response.statusCode) ? .success : .failed,
            errorCode: (200...299).contains(response.statusCode) ? nil : .http, durationMs: RuntimeLog.milliseconds(since: started),
            bytes: data.count, httpStatus: response.statusCode))
        switch response.statusCode {
        case 200...299: break
        case 401, 403: throw AIProviderPlugin.Failure(message: L10n.text("ai.error.authentication", spec.brand))
        case 402: throw AIProviderPlugin.Failure(message: L10n.text("ai.error.balance", spec.brand))
        case 429: throw AIProviderPlugin.Failure(message: L10n.text("ai.error.rate_limited", spec.brand))
        case 408, 504: throw AIProviderPlugin.Failure(message: L10n.text("ai.error.timeout", spec.brand), runtimeLogCode: .timeout)
        case 400, 422: throw AIProviderPlugin.Failure(message: L10n.text("ai.error.rejected", spec.brand))
        default: throw AIProviderPlugin.Failure(message: L10n.text("ai.error.http", spec.brand, response.statusCode))
        }
        var parsed = false
        log?.emit(.stageStarted, .init(stage: .format))
        defer { log?.emit(.stageFinished, .init(stage: .format, outcome: parsed ? .success : .failed, errorCode: parsed ? nil : .format)) }
        guard data.count <= 2_000_000,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]], choices.count == 1,
              let choice = choices.first else {
            throw AIProviderPlugin.Failure(message: L10n.text("ai.error.invalid_response", spec.brand))
        }
        if choice["finish_reason"] as? String == "length" {
            throw AIProviderPlugin.Failure(message: L10n.text("ai.error.truncated", spec.brand))
        }
        guard choice["finish_reason"] as? String == "stop",
              let message = choice["message"] as? [String: Any],
              message["tool_calls"] == nil || message["tool_calls"] is NSNull
                || (message["tool_calls"] as? [Any])?.isEmpty == true else {
            throw AIProviderPlugin.Failure(message: L10n.text("ai.error.incomplete", spec.brand))
        }
        guard let value = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw AIProviderPlugin.Failure(message: L10n.text("ai.error.empty", spec.brand))
        }
        let modelID = (object["model"] as? String).flatMap { $0.isEmpty ? nil : "\(spec.displayPrefix)/\($0)" }
        parsed = true
        return AIProviderPlugin.Response(result: value, error: nil, modelID: modelID)
    }

    /// 固定地址的请求不得跟随重定向，将记录与认证信息带到其他地址。
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static func validatedKey(_ value: String?, brand: String) throws -> String {
        let key = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            throw AIProviderPlugin.Failure(message: L10n.text("ai.error.missing_key", brand))
        }
        guard key.utf8.count <= 4096, key.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else {
            throw AIProviderPlugin.Failure(message: L10n.text("ai.error.invalid_key", brand))
        }
        return key
    }
}
