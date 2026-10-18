import Foundation

/// Native Messages transport. Text and thinking blocks stay separate; only complete answers are adopted.
enum Claude {
    @MainActor
    static func source(endpoint: URL, model: String,
                       readKey: @escaping @MainActor @Sendable () throws -> String?) -> AIProviderPlugin.Source {
        .init(id: "personal", title: model, detail: L10n.text("settings.ai.personal.privacy"),
              hasKey: { try readKey() != nil }, version: { _ in "claude/\(model)/v1" }, configure: { _ in
            let key = try OpenAICompatible.validatedKey(readKey(), brand: "Claude")
            // A provider may resolve an alias to a dated model. Verify the returned identity per response.
            return .init(version: "claude/\(model)/v1", providerID: "claude") { request in
                try await generate(request, endpoint: endpoint, model: model, key: key)
            }
        })
    }

    private static func generate(_ request: AIProviderPlugin.Request, endpoint: URL, model: String,
                                 key: String) async throws -> AIProviderPlugin.Response {
        // Some Claude models include reasoning in max_tokens; use the caller's declared total budget.
        let tokens = request.maximumTokensForThinkingModel ?? request.maximumTokens ?? 8192
        guard tokens > 0 else { throw failure(.configuration, "ai.error.rejected") }
        let streaming = request.streaming || request.onPartial != nil
        let instructions = request.instructions + (request.outputFormat == .json
            ? "\nReturn only valid JSON matching the requested structure, without Markdown fences." : "")
        let body: [String: Any] = ["model": model, "max_tokens": tokens, "stream": streaming,
            "system": instructions, "messages": [["role": "user", "content": request.content]]]
        var http = URLRequest(url: endpoint)
        http.httpMethod = "POST"; http.timeoutInterval = request.timeout
        http.setValue(key, forHTTPHeaderField: "x-api-key")
        http.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.httpBody = try JSONSerialization.data(withJSONObject: body)
        guard let data = http.httpBody, data.count <= request.maximumBytes else {
            throw failure(.inputTooLarge, "ai.error.request_too_large")
        }
        await ModelDiagnostics.current?.request(data, "claude", model, endpoint)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeout
        configuration.timeoutIntervalForResource = request.timeout
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            // Both modes are read with a bounded buffer and a cancellable task.
            let (bytes, response) = try await session.bytes(for: http, delegate: NoRedirect())
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse else { throw failure() }
            guard (200...299).contains(response.statusCode) else { throw httpFailure(response.statusCode) }
            if streaming { return try await stream(bytes, request: request) }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 2_000_000 else { throw failure() }
                data.append(byte)
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "message", object["role"] as? String == "assistant",
                  object["stop_reason"] as? String == "end_turn",
                  let blocks = object["content"] as? [[String: Any]] else { throw failure() }
            let observed = try modelIdentity(object["model"])
            var text = ""
            for block in blocks {
                switch block["type"] as? String {
                case "text":
                    guard let value = block["text"] as? String else { throw failure() }
                    text += value
                case "thinking", "redacted_thinking": break
                default: throw failure()
                }
            }
            return try result(text, model: observed, maximumBytes: request.maximumBytes)
        } catch let error as URLError {
            if Task.isCancelled || error.code == .cancelled { throw CancellationError() }
            throw failure(error.code == .timedOut ? .timeout : .disconnected,
                          error.code == .timedOut ? "ai.error.timeout" : "ai.error.disconnected")
        } catch is DecodingError { throw failure() }
        catch let error as NSError where error.domain == NSCocoaErrorDomain { throw failure() }
    }

    private static func stream(_ bytes: URLSession.AsyncBytes,
                               request: AIProviderPlugin.Request) async throws -> AIProviderPlugin.Response {
        var state = MessageStream(request: request)
        var line = Data(), event: [String] = [], count = 0
        for try await byte in bytes {
            try Task.checkCancellation()
            count += 1
            guard count <= 2_000_000 else { throw failure() }
            if byte != 10 { line.append(byte); continue }
            if line.last == 13 { line.removeLast() }
            guard let text = String(data: line, encoding: .utf8) else { throw failure() }
            line.removeAll(keepingCapacity: true)
            if text.isEmpty {
                if !event.isEmpty {
                    try await state.consume(event.joined(separator: "\n"))
                    event.removeAll(keepingCapacity: true)
                    if state.done { break }
                }
            } else if text.hasPrefix("data:") {
                let value = text.dropFirst(5)
                event.append(String(value.first == " " ? value.dropFirst() : value))
            }
        }
        try Task.checkCancellation()
        guard state.done, let model = state.model else { throw failure(.disconnected, "ai.error.disconnected") }
        return try result(state.text, model: model, maximumBytes: request.maximumBytes)
    }

    private struct MessageStream {
        let request: AIProviderPlugin.Request
        var model: String?
        var text = ""
        var block: (index: Int, type: String)?
        var nextIndex = 0
        var stopped = false
        var done = false

        mutating func consume(_ data: String) async throws {
            guard let object = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
                  let type = object["type"] as? String else { throw failure() }
            switch type {
            case "ping": return
            case "error": throw failure(.unavailable)
            case "message_start":
                guard model == nil, let message = object["message"] as? [String: Any],
                      message["role"] as? String == "assistant",
                      let content = message["content"] as? [Any], content.isEmpty else { throw failure() }
                model = try modelIdentity(message["model"])
            case "content_block_start":
                guard model != nil, !stopped, block == nil, let index = object["index"] as? Int,
                      index == nextIndex, let content = object["content_block"] as? [String: Any],
                      let kind = content["type"] as? String,
                      ["text", "thinking", "redacted_thinking"].contains(kind) else { throw failure() }
                block = (index, kind)
                if kind == "text" {
                    guard let value = content["text"] as? String else { throw failure() }
                    try await append(value)
                }
            case "content_block_delta":
                guard !stopped, let block, object["index"] as? Int == block.index,
                      let delta = object["delta"] as? [String: Any] else { throw failure() }
                if block.type == "text" {
                    guard delta["type"] as? String == "text_delta", let value = delta["text"] as? String else { throw failure() }
                    try await append(value)
                } else if !["thinking_delta", "signature_delta"].contains(delta["type"] as? String ?? "") { throw failure() }
            case "content_block_stop":
                guard let current = block, object["index"] as? Int == current.index else { throw failure() }
                block = nil; nextIndex += 1
            case "message_delta":
                guard model != nil, block == nil, !stopped,
                      let delta = object["delta"] as? [String: Any] else { throw failure() }
                if let reason = delta["stop_reason"] as? String {
                    guard reason == "end_turn" else { throw failure(.format, reason == "max_tokens" ? "ai.error.truncated" : "ai.error.incomplete") }
                    stopped = true
                }
            case "message_stop":
                guard model != nil, block == nil, stopped else { throw failure() }
                done = true
            default: break // Ignore future metadata events; known lifecycle markers remain mandatory.
            }
        }
        mutating func append(_ value: String) async throws {
            text += value
            guard text.utf8.count <= request.maximumBytes else { throw failure() }
            guard !value.isEmpty else { return }
            await ModelDiagnostics.current?.response(text, model, false)
            try await request.onPartial?(text)
        }
    }

    private static func modelIdentity(_ value: Any?) throws -> String {
        guard let value = value as? String, !value.isEmpty, value.utf8.count <= 256,
              !["unknown", "default", "auto"].contains(value.lowercased()),
              value.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else {
            throw failure(.modelUnknown, "ai.error.model_unknown")
        }
        return "claude/\(value)"
    }
    private static func result(_ text: String, model: String, maximumBytes: Int) throws -> AIProviderPlugin.Response {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= maximumBytes else { throw failure() }
        return .init(result: value, error: nil, modelID: model)
    }
    private static func failure(_ code: RuntimeLog.Code = .format,
                                _ key: String = "ai.error.invalid_response") -> AIProviderPlugin.Failure {
        .init(message: L10n.text(key, "Claude", 0), runtimeLogCode: code)
    }
    private static func httpFailure(_ status: Int) -> AIProviderPlugin.Failure {
        let code: RuntimeLog.Code
        let key: String
        switch status {
        case 401, 403: code = .authentication; key = "ai.error.authentication"
        case 429: code = .rateLimited; key = "ai.error.rate_limited"
        case 408, 504: code = .timeout; key = "ai.error.timeout"
        case 400, 422: code = .configuration; key = "ai.error.rejected"
        default: code = .http; key = "ai.error.http"
        }
        return .init(message: L10n.text(key, "Claude", status), runtimeLogCode: code, httpStatus: status)
    }
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
}
