import Foundation

/// Notes owns text processing compatibility; model-space defaults come from the capability catalog.
struct NotesEmbeddingProfile: Codable, Equatable, Sendable {
    var provider = ModelEmbeddingSpace.current.provider
    var endpoint = ModelEmbeddingSpace.current.endpoint
    var model = ModelEmbeddingSpace.current.model
    var dimension = ModelEmbeddingSpace.current.dimension
    var processingVersion = 3

    var identity: String { "\(provider)|\(endpoint)|\(model)|\(dimension)|\(processingVersion)" }
}
