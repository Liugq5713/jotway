import Foundation

struct NotesSource: Codable, Equatable, Sendable {
    let id: String
    let folderID: String
    let title: String
    let created: Date
    let modified: Date
    let locked: Bool
    let shared: Bool
}

struct NotesSourceBody: Sendable {
    let text: String
    let html: String
    let attachments: Int
}

/// Only the public Notes Apple Events interface. No private database or UI scraping.
struct AppleNotesReader: Sendable {
    var run: @MainActor @Sendable (AppleNotes.Request) async throws -> AppleNotes.Response = {
        try await AppleNotes.run($0)
    }

    func folders(allowAuthorization: Bool = false,
                 progress: (@MainActor @Sendable (Int) async -> Void)? = nil) async throws -> [AppleNotes.Destination] {
        let response = try await perform(.init(requestID: UUID().uuidString, operation: "folders",
                                              historyRead: true, allowAuthorization: allowAuthorization, folderProgress: progress))
        guard let folders = response.folders else { throw NotesHistoryError.response }
        return folders
    }

    func metadata(folderID: String,
                  progress: (@MainActor @Sendable (Int, Int) async -> Void)? = nil) async throws -> [NotesSource] {
        let response = try await perform(.init(requestID: UUID().uuidString, operation: "historyMetadata",
                                              folderID: folderID, historyRead: true, metadataProgress: progress))
        guard let sources = response.sources else { throw NotesHistoryError.response }
        return sources
    }

    func body(noteID: String) async throws -> NotesSourceBody {
        let response = try await perform(.init(requestID: UUID().uuidString, operation: "historyBody",
                                              noteID: noteID, historyRead: true))
        guard let body = response.sourceBody else { throw NotesHistoryError.response }
        return body
    }

    func open(noteID: String) async throws {
        _ = try await perform(.init(requestID: UUID().uuidString, operation: "historyOpen",
                                   noteID: noteID, historyRead: true, allowAuthorization: true))
    }

    private func perform(_ request: AppleNotes.Request) async throws -> AppleNotes.Response {
        try Task.checkCancellation()
        do {
            let response = try await run(request)
            try Task.checkCancellation()
            if let failure = AppleNotes.actionFailure(for: response, operation: request.operation) { throw failure }
            return response
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            throw AppleNotes.actionFailure(for: error, operation: request.operation)
        }
    }
}
