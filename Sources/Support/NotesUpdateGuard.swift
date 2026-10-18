import Foundation

/// Public-Notes preconditions for one managed update. Rechecked immediately before dispatch.
struct NotesUpdateGuard: Sendable {
    let noteID: String
    let scope: NotesDailyScope
    let boundary: NotesDailyBoundary

    func validate(source: NotesSource, body: NotesSourceBody, at now: Date = Date(),
                  timeZone: TimeZone = .current) throws {
        let today = NotesDailyScope.current(folderID: scope.folderID, at: now, timeZone: timeZone)
        guard today == scope, source.id == noteID, source.folderID == scope.folderID,
              NotesDailyScope.current(folderID: scope.folderID, at: source.created, timeZone: timeZone) == scope,
              !source.locked, !source.shared, body.attachments == 0,
              boundary.extract(from: NotesOriginalText.readableText(body)) != nil else {
            throw NotesReadError.stale
        }
    }
}
