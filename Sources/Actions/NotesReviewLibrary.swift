import AppKit
import Foundation
import Observation

/// Reads bounded original text only when a review is explicitly requested.
@MainActor @Observable
final class NotesReviewLibrary {
    let models: ModelConfiguration
    let origins: NotesOriginStore
    private let preferences: UserDefaults
    private let reader: AppleNotesReader
    private let checkPermission: @MainActor () -> Bool
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    private(set) var generation = 0
    private(set) var hasPermission = false
    private(set) var allFolders: Bool
    private(set) var selectedFolders: Set<String>
    private(set) var availableFolders: [AppleNotes.Destination] = []
    private(set) var authorizing = false
    private(set) var message: String?

    init(preferences: UserDefaults, models: ModelConfiguration? = nil,
         origins: NotesOriginStore = .init(), reader: AppleNotesReader = .init(),
         checkPermission: @escaping @MainActor () -> Bool = { AppleNotes.authorizationStatus() == 0 }) {
        self.preferences = preferences
        self.models = models ?? ModelConfiguration(preferences: preferences)
        self.origins = origins
        self.reader = reader
        self.checkPermission = checkPermission
        // Preserve the existing scope without retaining its retired feature switches.
        allFolders = preferences.object(forKey: "notesReview.allFolders") as? Bool
            ?? preferences.object(forKey: "notesHistory.allFolders") as? Bool ?? true
        selectedFolders = Set(preferences.stringArray(forKey: "notesReview.folders")
            ?? preferences.stringArray(forKey: "notesHistory.folders") ?? [])
        preferences.set(allFolders, forKey: "notesReview.allFolders")
        preferences.set(selectedFolders.sorted(), forKey: "notesReview.folders")
        hasPermission = checkPermission()
        activationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification).map({ _ in () }) {
                guard !Task.isCancelled else { return }
                self?.refreshPermission()
            }
        }
    }

    deinit { activationTask?.cancel() }

    func refreshPermission() {
        let granted = checkPermission()
        if granted != hasPermission { hasPermission = granted; generation &+= 1 }
    }

    func setAllFolders(_ value: Bool) {
        allFolders = value
        preferences.set(value, forKey: "notesReview.allFolders")
        generation &+= 1
    }

    func selectFolder(_ id: String, selected: Bool) {
        if selected { selectedFolders.insert(id) } else { selectedFolders.remove(id) }
        preferences.set(selectedFolders.sorted(), forKey: "notesReview.folders")
        generation &+= 1
    }

    func loadFolders() async {
        guard !authorizing else { return }
        authorizing = true
        defer { authorizing = false }
        do {
            availableFolders = try await reader.folders(allowAuthorization: true)
            refreshPermission()
            message = nil
        } catch { message = error.localizedDescription }
    }

    struct Selection: Sendable {
        let sources: [NotesReviewSource]
        let incomplete: Bool
    }

    func read(since start: Date, through end: Date, limit: Int) async throws -> Selection {
        refreshPermission()
        guard hasPermission else { throw NotesReadError.unavailable }
        let expected = generation
        let scope = allFolders ? nil : selectedFolders
        func validate() throws {
            try Task.checkCancellation()
            refreshPermission()
            guard hasPermission, generation == expected else { throw NotesReadError.stale }
        }
        let folders = try await reader.folders().filter { scope?.contains($0.id) ?? true }
        try validate()
        var incomplete = scope.map { !$0.isSubset(of: Set(folders.map(\.id))) } ?? false
        var candidates: [String: NotesSource] = [:]
        for folder in folders {
            let metadata = try await reader.metadata(folderID: folder.id)
            try validate()
            for source in metadata where source.modified >= start && source.modified <= end {
                candidates[source.id] = source
            }
        }
        let ordered = candidates.values.sorted {
            $0.modified == $1.modified ? $0.id < $1.id : $0.modified > $1.modified
        }
        incomplete = incomplete || ordered.count > limit
        var sources: [NotesReviewSource] = []
        for source in ordered.prefix(limit) {
            try validate()
            guard !source.locked else { incomplete = true; continue }
            do {
                let body = try await reader.body(noteID: source.id)
                try validate()
                let text = try await origins.originalText(noteID: source.id, body: body)
                try validate()
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    incomplete = true
                    continue
                }
                incomplete = incomplete || body.attachments > 0 || text.count > 4_000
                sources.append(.init(noteID: source.id, title: String(source.title.prefix(200)),
                    modified: source.modified, text: String(text.prefix(4_000))))
            } catch {
                try validate()
                if error is CancellationError { throw error }
                if let failure = error as? ActionFailure, [-1743, -1744].contains(failure.osStatus) { throw error }
                incomplete = true
            }
        }
        try validate()
        // A completely failed read is not a successful, cacheable empty review.
        guard ordered.isEmpty || !sources.isEmpty else { throw NotesReadError.unavailable }
        return .init(sources: sources, incomplete: incomplete)
    }
}
