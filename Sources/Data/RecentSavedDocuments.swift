import Foundation

struct RecentSavedDocument: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let savedAt: Date
}

/// Keep only confirmed document identities; detail content is read from Notes on demand.
@MainActor
final class RecentSavedDocuments {
    static let key = "notes.recentSavedDocuments.v1"
    private let defaults: UserDefaults?
    private(set) var documents: [RecentSavedDocument] = []

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        guard let data = defaults?.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode([RecentSavedDocument].self, from: data) else { return }
        var seen = Set<String>()
        documents = Array(stored.filter {
            Self.isValid($0) && seen.insert($0.id).inserted
        }.prefix(3))
    }

    func record(noteID: String, at date: Date = Date()) {
        let document = RecentSavedDocument(id: noteID, savedAt: date)
        guard Self.isValid(document) else { return }
        documents.removeAll { $0.id == noteID }
        documents.insert(document, at: 0)
        documents = Array(documents.prefix(3))
        guard let defaults, let data = try? JSONEncoder().encode(documents) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private static func isValid(_ document: RecentSavedDocument) -> Bool {
        NotesSourceLink.url(noteID: document.id) != nil && document.savedAt.timeIntervalSinceReferenceDate.isFinite
    }
}
