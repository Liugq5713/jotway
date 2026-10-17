import Foundation

struct NotesSyncProgress: Sendable {
    enum Stage: Sendable { case folders, metadata, checking, reading, embedding, saving, finishing }
    var stage: Stage = .folders
    var completed = 0
    /// Unknown until all selected folders have been scanned; zero is a real empty scan.
    var total: Int?
    var folder = 0
    var folderCount = 0
    var scanned = 0
    var fragmentsCompleted = 0
    var fragmentCount = 0
    var indexUpdated = false

    var description: String {
        switch stage {
        case .folders: folderCount == 0 ? L10n.text("notes.history.phase.folders")
            : L10n.text("notes.history.phase.found_folders", folderCount)
        case .metadata: L10n.text("notes.history.phase.metadata", folder, folderCount, scanned)
        case .checking: L10n.text("notes.history.phase.checking")
        case .reading: L10n.text("notes.history.phase.reading", completed + 1, total ?? 0)
        case .embedding: L10n.text("notes.history.phase.embedding", completed + 1, total ?? 0,
                                  fragmentsCompleted, fragmentCount)
        case .saving: L10n.text("notes.history.phase.saving")
        case .finishing: L10n.text("notes.history.phase.finishing")
        }
    }
}
