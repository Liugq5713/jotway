import Foundation

struct ModelEmbeddingSpace: Sendable {
    let provider: String
    let endpoint: String
    let model: String
    let dimension: Int
    static let current = Self(provider: "dashscope",
        endpoint: "",
        model: "qwen3.7-text-embedding", dimension: 1024)

    /// Each account supplies its own service URL; no workspace identity ships with the app.
    static func validEndpoint(_ value: String) -> Bool {
        guard let url = URLComponents(string: value), url.scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.port == nil || url.port == 443 else { return false }
        return host.hasSuffix(".maas.aliyuncs.com")
            && url.path == "/api/v1/services/embeddings/text-embedding/text-embedding"
    }
}

struct ModelEmbeddingRequest: Sendable {
    enum TextType: String, Sendable { case document, query }
    let texts: [String]
    let type: TextType
    var maximumBytes = 350_000
    var timeout: TimeInterval = 300
}

struct ModelEmbeddingInvocation: Sendable {
    typealias TextType = ModelEmbeddingRequest.TextType
    let profile: NotesEmbeddingProfile
    var validate: @Sendable () async throws -> Void = { try Task.checkCancellation() }
    let generate: @Sendable (ModelEmbeddingRequest) async throws -> [[Float]]

    func embed(_ texts: [String], type: TextType) async throws -> [[Float]] {
        try await call(.init(texts: texts, type: type))
    }
    func call(_ request: ModelEmbeddingRequest) async throws -> [[Float]] {
        let texts = request.texts
        guard !texts.isEmpty, texts.count <= 20,
              texts.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 16_384 }) else { throw NotesHistoryError.tooLarge }
        try await validate()
        let vectors = try await generate(request)
        try await validate()
        guard vectors.count == texts.count, vectors.allSatisfy({ Self.valid($0, dimension: profile.dimension) }) else {
            throw NotesHistoryError.response
        }
        return vectors
    }
    static func valid(_ vector: [Float], dimension: Int = 1024) -> Bool {
        vector.count == dimension && vector.allSatisfy(\.isFinite)
            && vector.contains(where: { $0 != 0 })
            && vector.reduce(0.0, { $0 + Double($1) * Double($1) }).isFinite
    }
}

extension ModelConfiguration {
    func embedding(validate: @escaping @Sendable () async throws -> Void = { try Task.checkCancellation() }) throws -> ModelEmbeddingInvocation {
        if let replacement = embeddingFactory {
            let invocation = try replacement(validate)
            guard invocation.profile == embeddingProfile else { throw NotesHistoryError.rebuild }
            return invocation
        }
        guard ModelEmbeddingSpace.validEndpoint(embeddingProfile.endpoint) else { throw NotesHistoryError.configuration }
        guard let key = try loadKey(.notesEmbedding) else { throw NotesHistoryError.authentication }
        let client = NotesEmbeddingClient(key: key, profile: embeddingProfile, validate: validate, transport: embeddingTransport)
        return .init(profile: embeddingProfile, validate: validate) { request in
            var frozen = client
            frozen.timeout = request.timeout; frozen.maximumBytes = min(350_000, request.maximumBytes)
            return try await frozen.embed(request.texts, type: request.type)
        }
    }
}
