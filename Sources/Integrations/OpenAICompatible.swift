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
        var thinking = false
    }

    static func source(_ spec: Spec,
                       readKey explicitReadKey: (@MainActor @Sendable () throws -> String?)? = nil,
                       session suppliedSession: URLSession? = nil) -> AIProviderPlugin.Source {
        let readKey: @MainActor @Sendable () throws -> String? = explicitReadKey ?? { try APIKeyStore.shared.load(for: spec.providerKey) }
        let network = URLSessionConfiguration.ephemeral
        network.timeoutIntervalForRequest = 300
        network.timeoutIntervalForResource = 300
        network.urlCache = nil
        network.httpCookieStorage = nil
        network.urlCredentialStorage = nil
        let session = suppliedSession ?? URLSession(configuration: network)
        let model = "\(spec.displayPrefix)/\(spec.modelID)"
        let version = "\(model)/v1"
        return .init(id: spec.id, title: spec.title,
            detail: spec.detail,
            keyURL: spec.keyURL,
            hasKey: { try readKey() != nil },
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
        http.timeoutInterval = request.timeout
        http.cachePolicy = .reloadIgnoringLocalCacheData
        http.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let tokens = spec.thinking ? request.maximumTokensForThinkingModel : request.maximumTokens ?? spec.maxTokens
        guard let tokens, tokens > 0 else {
            throw AIProviderPlugin.Failure(message: "A thinking token budget is required", runtimeLogCode: .configuration)
        }
        let streaming = request.streaming || request.onPartial != nil
        var body: [String: Any] = [
            "model": spec.modelID, "stream": streaming,
            "max_tokens": tokens,
            "messages": [["role": "system", "content": request.instructions],
                         ["role": "user", "content": request.content]]
        ]
        for (field, value) in spec.extraBody { body[field] = value }
        guard (request.maximumTokens ?? spec.maxTokens) > 0 else {
            throw AIProviderPlugin.Failure(message: "Unsupported token budget", runtimeLogCode: .configuration)
        }
        if request.outputFormat == .json { body["response_format"] = ["type": "json_object"] }
        http.httpBody = try JSONSerialization.data(withJSONObject: body)
        guard (http.httpBody?.count ?? 0) <= request.maximumBytes else {
            throw AIProviderPlugin.Failure(message: L10n.text("ai.error.request_too_large"), runtimeLogCode: .inputTooLarge)
        }
        if let body = http.httpBody {
            await ModelDiagnostics.current?.request(body, spec.id, model, spec.baseURL)
        }
        if streaming {
            return try await stream(http, request: request, spec: spec, session: session)
        }
        let log = RuntimeLog.current
        let started = RuntimeLog.ticks()
        log?.emit(.stageStarted, .init(stage: .service, requestedModel: model))
        let data: Data
        let response: URLResponse
        do {
            // The adapter preserves the direct caller's request timeout.
            if request.timeout == .infinity {
                let configuration = session.configuration
                configuration.timeoutIntervalForRequest = request.timeout
                configuration.timeoutIntervalForResource = request.timeout
                let unlimited = URLSession(configuration: configuration)
                defer { unlimited.invalidateAndCancel() }
                (data, response) = try await unlimited.data(for: http, delegate: NoRedirect())
            } else {
                (data, response) = try await session.data(for: http, delegate: NoRedirect())
            }
        } catch {
            log?.failed(.service, error)
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if (error as? URLError)?.code == .timedOut {
                throw AIProviderPlugin.Failure(message: L10n.text("ai.error.timeout", spec.brand), runtimeLogCode: .timeout)
            }
            // 不把网络错误中的请求、认证头或服务端原始响应写入记录错误字段。
            throw AIProviderPlugin.Failure(message: L10n.text("ai.error.disconnected", spec.brand), runtimeLogCode: transportCode(error))
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw AIProviderPlugin.Failure(message: L10n.text("ai.error.invalid_response", spec.brand))
        }
        log?.emit(.stageFinished, .init(stage: .service, outcome: (200...299).contains(response.statusCode) ? .success : .failed,
            errorCode: (200...299).contains(response.statusCode) ? nil : .http, durationMs: RuntimeLog.milliseconds(since: started),
            bytes: data.count, httpStatus: response.statusCode))
        if !(200...299).contains(response.statusCode) { throw httpFailure(response, spec: spec) }
        var parsed = false
        log?.emit(.stageStarted, .init(stage: .format))
        defer { log?.emit(.stageFinished, .init(stage: .format, outcome: parsed ? .success : .failed, errorCode: parsed ? nil : .format)) }
        guard data.count <= 2_000_000,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]], choices.count == 1,
              let choice = choices.first else {
            throw AIProviderPlugin.Failure(message: L10n.text("ai.error.invalid_response", spec.brand), runtimeLogCode: .format)
        }
        if choice["finish_reason"] as? String == "length" {
            throw AIProviderPlugin.Failure(message: L10n.text("ai.error.truncated", spec.brand), runtimeLogCode: .format)
        }
        guard choice["finish_reason"] as? String == "stop",
              let message = choice["message"] as? [String: Any],
              message["tool_calls"] == nil || message["tool_calls"] is NSNull
                || (message["tool_calls"] as? [Any])?.isEmpty == true else {
            throw AIProviderPlugin.Failure(message: L10n.text("ai.error.incomplete", spec.brand), runtimeLogCode: .format)
        }
        guard let value = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw AIProviderPlugin.Failure(message: L10n.text("ai.error.empty", spec.brand), runtimeLogCode: .format)
        }
        let modelID = (object["model"] as? String).flatMap { $0.isEmpty ? nil : "\(spec.displayPrefix)/\($0)" }
        parsed = true
        return AIProviderPlugin.Response(result: value, error: nil, modelID: modelID)
    }

    /// Typed metadata lets an individual caller opt into retries without changing other flows.
    static func retryDelay(_ value: String?, at date: Date = Date()) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite, seconds >= 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(date)) }
    }

    private static func httpFailure(_ response: HTTPURLResponse, spec: Spec) -> AIProviderPlugin.Failure {
        let status = response.statusCode
        let key: String
        let code: RuntimeLog.Code
        switch status {
        case 401, 403: key = "ai.error.authentication"; code = .authentication
        case 402: key = "ai.error.balance"; code = .configuration
        case 429: key = "ai.error.rate_limited"; code = .rateLimited
        case 408, 504: key = "ai.error.timeout"; code = .timeout
        case 400, 422: key = "ai.error.rejected"; code = .configuration
        default: key = "ai.error.http"; code = .http
        }
        return .init(message: L10n.text(key, spec.brand, status), runtimeLogCode: code,
                     retryAfter: retryDelay(response.value(forHTTPHeaderField: "Retry-After")), httpStatus: status)
    }

    private static func stream(_ http: URLRequest, request: AIProviderPlugin.Request,
                               spec: Spec, session: URLSession) async throws -> AIProviderPlugin.Response {
        // URLSession has separate idle and resource deadlines; the model chain also enforces a hard deadline.
        let configuration = session.configuration
        configuration.timeoutIntervalForRequest = request.timeout
        configuration.timeoutIntervalForResource = request.timeout
        let streamingSession = URLSession(configuration: configuration)
        defer { streamingSession.invalidateAndCancel() }
        do {
            let (bytes, response) = try await streamingSession.bytes(for: http, delegate: NoRedirect())
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse else { throw invalidResponse(spec) }
            if !(200...299).contains(response.statusCode) { throw httpFailure(response, spec: spec) }
            var stream = CompletionStream(spec: spec, request: request)
            var line = Data(), event = [String](), count = 0
            for try await byte in bytes {
                try Task.checkCancellation()
                count += 1
                guard count <= 2_000_000 else { throw invalidResponse(spec) }
                if byte != 10 { line.append(byte); continue }
                if line.last == 13 { line.removeLast() }
                guard let text = String(data: line, encoding: .utf8) else { throw invalidResponse(spec) }
                line.removeAll(keepingCapacity: true)
                if text.isEmpty {
                    if !event.isEmpty {
                        try await stream.consume(event.joined(separator: "\n"))
                        event.removeAll(keepingCapacity: true)
                        if stream.done { break }
                    }
                } else if text.hasPrefix("data:") {
                    let value = text.dropFirst(5)
                    event.append(String(value.first == " " ? value.dropFirst() : value))
                }
            }
            try Task.checkCancellation()
            guard stream.done, stream.stopped else {
                // A clean HTTP EOF can still truncate the SSE protocol. The chain may
                // switch once, just as for a connection lost before either marker.
                throw AIProviderPlugin.Failure(message: L10n.text("ai.error.disconnected", spec.brand), runtimeLogCode: .disconnected)
            }
            let content = stream.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                throw AIProviderPlugin.Failure(message: L10n.text("ai.error.empty", spec.brand), runtimeLogCode: .format)
            }
            return .init(result: content, error: nil, modelID: stream.modelID)
        } catch let error as URLError {
            if Task.isCancelled || error.code == .cancelled { throw CancellationError() }
            throw AIProviderPlugin.Failure(message: L10n.text(
                error.code == .timedOut ? "ai.error.timeout" : "ai.error.disconnected", spec.brand),
                runtimeLogCode: transportCode(error))
        }
    }

    private struct CompletionStream {
        let spec: Spec
        let request: AIProviderPlugin.Request
        var content = ""
        var modelID: String?
        var stopped = false
        var done = false

        mutating func consume(_ data: String) async throws {
            if data == "[DONE]" {
                guard stopped else { throw invalidResponse(spec) }
                done = true
                return
            }
            guard let object = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
                  object["error"] == nil || object["error"] is NSNull,
                  let choices = object["choices"] as? [[String: Any]], choices.count <= 1 else {
                throw invalidResponse(spec)
            }
            if object["model"] != nil {
                guard let observed = object["model"] as? String, !observed.isEmpty else {
                    throw AIProviderPlugin.Failure(message: L10n.text("ai.error.model_unknown"), runtimeLogCode: .modelUnknown)
                }
                let qualified = "\(spec.displayPrefix)/\(observed)"
                guard qualified == request.modelID, modelID == nil || modelID == qualified else {
                    throw AIProviderPlugin.Failure(message: L10n.text("ai.error.model_mismatch"), runtimeLogCode: .modelMismatch)
                }
                modelID = qualified
            }
            guard let choice = choices.first else {
                guard object["usage"] is [String: Any] else { throw invalidResponse(spec) }
                return // Optional usage-only event.
            }
            guard !stopped, choice["index"] as? Int == 0,
                  let delta = choice["delta"] as? [String: Any],
                  delta["role"] == nil || delta["role"] is NSNull || delta["role"] as? String == "assistant",
                  delta["function_call"] == nil || delta["function_call"] is NSNull,
                  delta["tool_calls"] == nil || delta["tool_calls"] is NSNull
                    || (delta["tool_calls"] as? [Any])?.isEmpty == true,
                  delta["content"] == nil || delta["content"] is NSNull || delta["content"] is String else {
                throw invalidResponse(spec)
            }
            if let rawReason = choice["finish_reason"], !(rawReason is NSNull) {
                guard let reason = rawReason as? String else { throw invalidResponse(spec) }
                guard reason == "stop" else {
                    throw AIProviderPlugin.Failure(message: L10n.text(
                        reason == "length" ? "ai.error.truncated" : "ai.error.incomplete", spec.brand), runtimeLogCode: .format)
                }
                stopped = true
            }
            if let fragment = delta["content"] as? String, !fragment.isEmpty {
                guard modelID != nil else {
                    throw AIProviderPlugin.Failure(message: L10n.text("ai.error.model_unknown"), runtimeLogCode: .modelUnknown)
                }
                content += fragment
                guard content.utf8.count <= request.maximumBytes else { throw invalidResponse(spec) }
                await ModelDiagnostics.current?.response(content, modelID, false)
                try await request.onPartial?(content)
            }
        }
    }

    private static func transportCode(_ error: Error) -> RuntimeLog.Code {
        guard let error = error as? URLError else { return .unavailable }
        if error.code == .timedOut { return .timeout }
        return [.networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed]
            .contains(error.code) ? .disconnected : .unavailable
    }

    private static func invalidResponse(_ spec: Spec) -> AIProviderPlugin.Failure {
        .init(message: L10n.text("ai.error.invalid_response", spec.brand), runtimeLogCode: .format)
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
            throw AIProviderPlugin.Failure(message: L10n.text("ai.error.missing_key", brand), runtimeLogCode: .configuration)
        }
        guard key.utf8.count <= 4096, key.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else {
            throw AIProviderPlugin.Failure(message: L10n.text("ai.error.invalid_key", brand), runtimeLogCode: .configuration)
        }
        return key
    }
}
