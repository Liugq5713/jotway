import Foundation

/// The public service URL is built in; only per-user activation credentials are stored on the Mac.
enum HostedAI {
    static let sourceID = "jotway"
    static let baseURL = URL(string: "https://jotway-ai-service.liugq5713-437.workers.dev")!
    static let fastModel = "deepseek-flash"
    static let deepModel = "deepseek-v4-pro"
    static let models = [fastModel, deepModel, "kimi-k2.6"]

    enum Problem: String, Sendable, Equatable {
        case invalid, disabled, insufficientQuota, duplicate, busy, tooLarge, rejected, unavailable, unreachable
        var message: String {
            let key: String
            switch self {
            case .insufficientQuota: key = "settings.activation.empty"
            case .tooLarge: key = "ai.error.request_too_large"
            default: key = "settings.activation." + rawValue
            }
            return L10n.text(key)
        }
    }
    static func problem(_ error: Error) -> Problem? {
        (error as? AIProviderPlugin.Failure)?.hostedProblem
    }

    struct Account: Decodable, Sendable {
        let id: String
        let label: String
        let disabled: Bool
        let quota: Quota
        struct Quota: Decodable, Sendable {
            let unit: String
            let granted: Int
            let used: Int
            let held: Int
            let available: Int
        }
    }

    static func validCode(_ value: String) -> Bool {
        value.hasPrefix("jtw_live_") && value.utf8.count == 73
            && value.dropFirst(9).utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func source() -> AIProviderPlugin.Source {
        .init(id: sourceID, title: "Jotway AI", models: models.map { ($0, $0) },
              detail: L10n.text("settings.activation.privacy"),
              hasKey: { try ActivationCodeStore.shared.load() != nil },
              version: { "jotway/\($0 ?? deepModel)/v1" }, configure: { selected in
            let model = selected ?? deepModel
            guard models.contains(model), let code = try ActivationCodeStore.shared.load() else {
                throw AIProviderPlugin.Failure(message: L10n.text("settings.activation.required"), runtimeLogCode: .configuration)
            }
            return try adapter(model: model, readCode: { code }).configure(nil)
        })
    }

    // Shared adapter retains exact model checks, redirect refusal and strict stream completion.
    static func adapter(model: String, readCode: @escaping @MainActor @Sendable () throws -> String?,
                        session: URLSession? = nil) -> AIProviderPlugin.Source {
        let source = OpenAICompatible.source(.init(id: sourceID, title: "Jotway AI", brand: "Jotway AI", providerKey: nil,
            baseURL: baseURL.appendingPathComponent("v1/chat/completions"), modelID: model, displayPrefix: sourceID,
            keyURL: baseURL, detail: L10n.text("settings.activation.privacy"),
            idempotent: true, maximumTokenLimit: 8192, requestBodyLimit: 128 * 1024,
            httpError: { failure(status: $0) }), readKey: readCode, session: session)
        return .init(id: source.id, title: source.title, detail: source.detail,
                     version: source.version, configure: { model in
            let configuration = try source.configure(model)
            return .init(version: configuration.version, modelID: configuration.modelID, providerID: configuration.providerID) { request in
                do { return try await configuration.perform(request) }
                catch var error as AIProviderPlugin.Failure {
                    if error.hostedProblem == nil, [.timeout, .disconnected].contains(error.runtimeLogCode) {
                        error.hostedProblem = .unreachable
                    }
                    throw error
                }
            }
        })
    }

    static func account(code: String, session suppliedSession: URLSession? = nil) async throws -> Account {
        guard validCode(code) else { throw failure(status: 401) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = suppliedSession ?? URLSession(configuration: configuration)
        defer { if suppliedSession == nil { session.invalidateAndCancel() } }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/me"))
        request.setValue("Bearer \(code)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request, delegate: NoRedirect())
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw failure(status: 503) }
            guard response.statusCode == 200 else { throw failure(status: response.statusCode) }
            guard data.count < 16_384, let account = try? JSONDecoder().decode(Account.self, from: data),
                  !account.id.isEmpty, account.quota.unit == "token",
                  account.quota.available >= 0, account.quota.used >= 0, account.quota.held >= 0 else {
                throw failure(status: 503)
            }
            guard !account.disabled else { throw failure(status: 403) }
            return account
        } catch let error as URLError {
            if Task.isCancelled || error.code == .cancelled { throw CancellationError() }
            throw AIProviderPlugin.Failure(message: L10n.text("settings.activation.unreachable"), runtimeLogCode: .disconnected, hostedProblem: .unreachable)
        }
    }

    static func failure(status: Int) -> AIProviderPlugin.Failure {
        let problem: Problem
        let code: RuntimeLog.Code
        switch status {
        case 401: problem = .invalid; code = .authentication
        case 403: problem = .disabled; code = .authentication
        case 402: problem = .insufficientQuota; code = .configuration
        case 409: problem = .duplicate; code = .configuration
        case 429: problem = .busy; code = .rateLimited
        case 413: problem = .tooLarge; code = .inputTooLarge
        case 400, 422: problem = .rejected; code = .configuration
        default: problem = .unavailable; code = .unavailable
        }
        return .init(message: problem.message, runtimeLogCode: code, httpStatus: status, hostedProblem: problem)
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
    }
}
