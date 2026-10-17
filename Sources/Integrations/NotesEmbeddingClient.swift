import Foundation


enum NotesHistoryError: Error, LocalizedError, RuntimeLogError {
    case authentication, configuration, response, unavailable, rebuild, stale, tooLarge, busy, ambiguous
    var errorDescription: String? { L10n.text("notes.history.error.\(self)") }
    var runtimeLogCode: RuntimeLog.Code {
        switch self {
        case .stale: .stale
        case .authentication: .authentication
        case .response, .ambiguous: .validation
        case .tooLarge: .inputTooLarge
        case .rebuild, .configuration: .configuration
        case .unavailable, .busy: .unavailable
        }
    }
}

/// Separate foreground/background lanes: indexing cannot occupy the query lane.
private actor NotesEmbeddingGate {
    static let shared = NotesEmbeddingGate()
    private var active = Set<String>()
    private var waiting = 0
    func enter(_ lane: String) async throws {
        guard waiting < 8 else { throw NotesHistoryError.busy }
        waiting += 1
        defer { waiting -= 1 }
        while active.contains(lane) {
            try await Task.sleep(for: .milliseconds(25))
        }
        try Task.checkCancellation()
        active.insert(lane)
    }
    func leave(_ lane: String) { active.remove(lane) }
}

struct NotesEmbeddingClient: Sendable {
    typealias TextType = ModelEmbeddingRequest.TextType
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)
    let key: String
    var profile = NotesEmbeddingProfile()
    var maximumBytes = 350_000
    var timeout: TimeInterval = 300
    var validate: @Sendable () async throws -> Void = { try Task.checkCancellation() }
    var transport: Transport = Self.send

    private struct Request: Encodable {
        struct Input: Encodable { let texts: [String] }
        struct Parameters: Encodable {
            let dimension: Int
            let output_type = "dense"
            let text_type: String
        }
        let model: String
        let input: Input
        let parameters: Parameters
    }
    private struct Response: Decodable {
        struct Output: Decodable {
            struct Embedding: Decodable { let text_index: Int; let embedding: [Float] }
            let embeddings: [Embedding]
        }
        let output: Output
    }

    func embed(_ texts: [String], type: TextType) async throws -> [[Float]] {
        guard !texts.isEmpty, texts.count <= 20,
              texts.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 16_384 }) else { throw NotesHistoryError.tooLarge }
        let body = try JSONEncoder().encode(Request(model: profile.model, input: .init(texts: texts),
            parameters: .init(dimension: profile.dimension, text_type: type.rawValue)))
        guard body.count <= maximumBytes, let url = URL(string: profile.endpoint) else { throw NotesHistoryError.tooLarge }
        try await validate()
        try await NotesEmbeddingGate.shared.enter(type.rawValue)
        do {
            let result = try await request(body, url: url, count: texts.count)
            await NotesEmbeddingGate.shared.leave(type.rawValue)
            return result
        } catch {
            await NotesEmbeddingGate.shared.leave(type.rawValue)
            throw error
        }
    }

    private func request(_ body: Data, url: URL, count: Int) async throws -> [[Float]] {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for attempt in 0..<3 {
            try Task.checkCancellation()
            try await validate()
            do {
                let (data, status) = try await transport(request)
                try Task.checkCancellation()
                try await validate()
                if status == 401 || status == 403 { throw NotesHistoryError.authentication }
                if status == 429 || (500...599).contains(status) {
                    if attempt < 2 { try await Task.sleep(for: .seconds(attempt + 1)); continue }
                    throw NotesHistoryError.unavailable
                }
                guard status == 200 else { throw NotesHistoryError.response }
                return try Self.decode(data, count: count, dimension: profile.dimension)
            } catch let error as URLError {
                try Task.checkCancellation()
                if error.code == .cancelled { throw CancellationError() }
                guard attempt < 2, [.timedOut, .networkConnectionLost, .notConnectedToInternet,
                                    .cannotConnectToHost, .dnsLookupFailed].contains(error.code) else {
                    throw NotesHistoryError.unavailable
                }
                try await Task.sleep(for: .seconds(attempt + 1))
            }
        }
        throw NotesHistoryError.unavailable
    }

    static func decode(_ data: Data, count: Int, dimension: Int = 1024) throws -> [[Float]] {
        guard data.count <= 2_000_000,
              let response = try? JSONDecoder().decode(Response.self, from: data),
              response.output.embeddings.count == count else { throw NotesHistoryError.response }
        var result = Array<[Float]?>(repeating: nil, count: count)
        for value in response.output.embeddings {
            guard result.indices.contains(value.text_index), result[value.text_index] == nil,
                  valid(value.embedding, dimension: dimension) else { throw NotesHistoryError.response }
            let norm = sqrt(value.embedding.reduce(0.0) { $0 + Double($1) * Double($1) })
            result[value.text_index] = value.embedding.map { Float(Double($0) / norm) }
        }
        guard result.allSatisfy({ $0 != nil }) else { throw NotesHistoryError.response }
        return result.compactMap { $0 }
    }

    static func valid(_ vector: [Float], dimension: Int = 1024) -> Bool {
        vector.count == dimension && vector.allSatisfy(\.isFinite)
            && vector.contains(where: { $0 != 0 })
            && vector.reduce(0.0, { $0 + Double($1) * Double($1) }).isFinite
    }

    static func send(_ request: URLRequest) async throws -> (Data, Int) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw NotesHistoryError.response }
        guard response.expectedContentLength <= 2_000_000 else { throw NotesHistoryError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            if data.count >= 2_000_000 { throw NotesHistoryError.tooLarge }
            data.append(byte)
        }
        return (data, response.statusCode)
    }
}
