import Foundation

/// An explicit, read-only directory request. A listed model is not proof of text support.
enum PersonalModelCatalog {
    struct Model: Identifiable, Sendable {
        let id: String
        let name: String
        var title: String { name == id ? id : "\(name) (\(id))" }
    }

    struct Result: Sendable {
        let models: [Model]
        let isPartial: Bool
    }

    private struct Failure: LocalizedError {
        let key: String
        var errorDescription: String? { L10n.text(key) }
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static func load(configuration: PersonalModelConfiguration, key: String) async throws -> Result {
        let value = try configuration.normalizedDestination()
        let key = try OpenAICompatible.validatedKey(key, brand: "AI")
        var endpoint = URLComponents(url: URL(string: value.baseURL)!.appendingPathComponent("models"),
                                     resolvingAgainstBaseURL: false)!
        if value.service == .claude { endpoint.queryItems = [.init(name: "limit", value: "1000")] }
        var request = URLRequest(url: endpoint.url!, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if value.service == .claude {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = 20
        settings.timeoutIntervalForResource = 20
        settings.urlCache = nil
        settings.httpCookieStorage = nil
        settings.urlCredentialStorage = nil
        let session = URLSession(configuration: settings)
        defer { session.invalidateAndCancel() }
        do {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request, delegate: NoRedirect())
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse else { throw failure("invalid") }
            guard (200...299).contains(response.statusCode) else {
                switch response.statusCode {
                case 401, 403: throw failure("auth")
                case 404, 405: throw failure("unsupported")
                case 408, 504: throw failure("timeout")
                case 429: throw failure("rate")
                case 300...399: throw failure("redirect")
                default: throw failure("unavailable")
                }
            }
            guard response.expectedContentLength <= 2_000_000 else { throw failure("large") }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 2_000_000 else { throw failure("large") }
                data.append(byte)
            }
            try Task.checkCancellation()
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = object["data"] as? [[String: Any]] else { throw failure("invalid") }
            var models: [Model] = [], seen = Set<String>()
            for row in rows.prefix(1000) {
                try Task.checkCancellation()
                guard let id = row["id"] as? String, PersonalModelConfiguration.isValidModelID(id),
                      seen.insert(id).inserted else { continue }
                // Only exclude models when the service explicitly declares non-text output.
                if let outputs = row["output_modalities"] as? [String], !outputs.contains("text") { continue }
                let name = (row["display_name"] ?? row["name"]) as? String ?? id
                let safeName = !name.isEmpty && name.utf8.count <= 256 &&
                    name.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
                models.append(.init(id: id, name: safeName ? name : id))
            }
            return .init(models: models.sorted { $0.id < $1.id },
                         isPartial: rows.count > 1000 || object["has_more"] as? Bool == true)
        } catch let error as URLError {
            if Task.isCancelled || error.code == .cancelled { throw CancellationError() }
            throw failure(error.code == .timedOut ? "timeout" : "network")
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as Failure {
            throw error
        } catch {
            throw failure("invalid")
        }
    }

    private static func failure(_ suffix: String) -> Failure {
        Failure(key: "settings.ai.catalog.error." + suffix)
    }
}
