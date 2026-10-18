import Foundation
import CryptoKit
import GRDB
import CSQLiteVec

enum NotesTextHash {
    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// One recently modified note, with generated regions excluded before periodic review.
struct NotesReviewSource: Equatable, Sendable, Identifiable {
    let noteID: String
    let title: String
    let modified: Date
    let text: String
    var id: String { noteID }
}

/// Original/generated boundaries only; no searchable text or vectors remain after migration.
actor NotesOriginStore {
    private let url: URL
    private var queue: DatabaseQueue?

    init(url: URL = StorageLocation.appSupport.appendingPathComponent("notes-index.sqlite")) {
        self.url = url
    }

    private func database() throws -> DatabaseQueue {
        if let queue { return queue }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            guard sqlite3_vec_init(db.sqliteConnection, nil, nil) == 0 else { throw NotesReadError.unavailable }
        }
        let result = try DatabaseQueue(path: url.path, configuration: configuration)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_notes_index") { db in
            try db.execute(sql: """
                CREATE TABLE index_state (id INTEGER PRIMARY KEY CHECK(id=1), profile TEXT NOT NULL,
                    version INTEGER NOT NULL DEFAULT 0, lastSuccess DOUBLE, checkpoint TEXT);
                CREATE TABLE sources (id TEXT PRIMARY KEY, folderID TEXT NOT NULL, title TEXT NOT NULL,
                    created DOUBLE NOT NULL, modified DOUBLE NOT NULL, shared INTEGER NOT NULL,
                    state TEXT NOT NULL, bodyHash TEXT NOT NULL, attachments INTEGER NOT NULL);
                CREATE TABLE chunks (id INTEGER PRIMARY KEY, sourceID TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
                    ordinal INTEGER NOT NULL, offset INTEGER NOT NULL, text TEXT NOT NULL, hash TEXT NOT NULL,
                    provenance TEXT NOT NULL DEFAULT 'recorded_in_note');
                CREATE INDEX chunk_hash ON chunks(hash);
                CREATE INDEX chunk_source ON chunks(sourceID);
                CREATE VIRTUAL TABLE vectors USING vec0(id INTEGER PRIMARY KEY,
                    embedding FLOAT[1024] distance_metric=cosine, folder_id TEXT PARTITION KEY);
                """)
        }
        migrator.registerMigration("v2_original_boundaries") { db in
            try db.execute(sql: """
                ALTER TABLE sources ADD COLUMN processingVersion INTEGER NOT NULL DEFAULT 1;
                CREATE TABLE origins (token TEXT PRIMARY KEY, noteID TEXT, originalHash TEXT NOT NULL,
                    originalLength INTEGER NOT NULL, tailHash TEXT NOT NULL, tailLength INTEGER NOT NULL,
                    formatVersion INTEGER NOT NULL);
                CREATE UNIQUE INDEX origin_note ON origins(noteID);
                """)
        }
        migrator.registerMigration("v3_daily_original_boundaries") { db in
            try db.execute(sql: """
                CREATE TABLE daily_origins (token TEXT PRIMARY KEY, noteID TEXT UNIQUE,
                    targetID TEXT, boundary BLOB NOT NULL);
                """)
        }
        let needsCleanup = try result.read { db in
            try db.tableExists("chunks")
        }
        migrator.registerMigration("v4_remove_related_history") { db in
            try db.execute(sql: "DROP TABLE vectors; DROP TABLE chunks; DROP TABLE sources; DROP TABLE index_state;")
        }
        try migrator.migrate(result)
        if needsCleanup {
            try result.writeWithoutTransaction { try $0.execute(sql: "VACUUM") }
        }
        queue = result
        return result
    }

    /// Persist before sending create. A pending fingerprint also covers uncertain writes.
    func stageOrigin(original: String, content: AppleNotes.Content) throws -> String {
        let normalized = original.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let origin = NotesOrigin(original: original, generated: String(content.plaintext.dropFirst(normalized.count)))
        let token = UUID().uuidString
        try database().write { db in
            try storeOrigin(origin, token: token, noteID: nil, db: db)
        }
        return token
    }

    func confirmOrigin(token: String, noteID: String) throws {
        try database().write { db in
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM origins WHERE token=?", arguments: [token]) == 1
            else { throw NotesReadError.stale }
            try db.execute(sql: "DELETE FROM origins WHERE noteID=? AND token<>?", arguments: [noteID, token])
            try db.execute(sql: "UPDATE origins SET noteID=? WHERE token=?", arguments: [noteID, token])
        }
    }

    func stageDailyOrigin(noteID: String?, boundary: NotesDailyBoundary) throws -> String {
        let token = UUID().uuidString
        try database().write { db in
            try db.execute(sql: "INSERT INTO daily_origins VALUES (?, NULL, ?, ?)",
                           arguments: [token, noteID, try JSONEncoder().encode(boundary)])
        }
        return token
    }

    func confirmDailyOrigin(token: String, noteID: String) throws {
        try database().write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM daily_origins WHERE token=?", arguments: [token]),
                  (row["targetID"] as String?).map({ $0 == noteID }) ?? true else { throw NotesReadError.stale }
            try db.execute(sql: "DELETE FROM daily_origins WHERE noteID=? AND token<>?", arguments: [noteID, token])
            try db.execute(sql: "UPDATE daily_origins SET noteID=?, targetID=? WHERE token=?", arguments: [noteID, noteID, token])

        }
    }

    func discardDailyOrigin(token: String) throws {
        try database().write { db in
            try db.execute(sql: "DELETE FROM daily_origins WHERE token=? AND noteID IS NULL", arguments: [token])
        }
    }

    /// Only definite non-writes may discard provenance. Uncertain writes retain protection.
    func discardOrigin(token: String) throws {
        try database().write { db in
            try db.execute(sql: "DELETE FROM origins WHERE token=? AND noteID IS NULL", arguments: [token])
        }
    }

    private func storeOrigin(_ origin: NotesOrigin, token: String, noteID: String?, db: GRDB.Database) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO origins VALUES (?, ?, ?, ?, ?, ?, ?)",
                       arguments: [token, noteID, origin.hash, origin.length, origin.tailHash, origin.tailLength, origin.formatVersion])
    }

    /// Extract only verified originals for review; generated additions never become user evidence.
    func originalText(noteID: String, body: NotesSourceBody) throws -> String {
        guard body.text.utf8.count <= 2_000_000, body.html.utf8.count <= 4_000_000 else { throw NotesReadError.tooLarge }
        let result: Result<String, Error> = try database().write { db in
            let readable = NotesOriginalText.readableText(body)
            let dailyRows = try Row.fetchAll(db, sql: """
                SELECT * FROM daily_origins WHERE noteID=? OR
                    (noteID IS NULL AND (targetID=? OR targetID IS NULL))
                ORDER BY noteID IS NULL DESC
                """, arguments: [noteID, noteID])
            for row in dailyRows {
                let boundary = try JSONDecoder().decode(NotesDailyBoundary.self, from: row["boundary"] as Data)
                if let parts = boundary.extract(from: readable) {
                    return .success(parts.filter { $0.kind == .original }.map(\.text).joined(separator: "\n\n"))
                }
            }
            if dailyRows.contains(where: { ($0["noteID"] as String?) == noteID || ($0["targetID"] as String?) == noteID }) {
                return .failure(NotesReadError.ambiguous)
            }
            func origin(_ row: Row) -> NotesOrigin {
                .init(hash: row["originalHash"], length: row["originalLength"], tailHash: row["tailHash"],
                      tailLength: row["tailLength"], formatVersion: row["formatVersion"])
            }
            if let row = try Row.fetchOne(db, sql: "SELECT * FROM origins WHERE noteID=?", arguments: [noteID]) {
                return Result { try NotesOriginalText.extract(body, origin: origin(row)) }
            }
            var uncertainTail = false
            for row in try Row.fetchAll(db, sql: "SELECT * FROM origins WHERE noteID IS NULL") {
                let pending = origin(row)
                if pending.original(in: readable) != nil {
                    try storeOrigin(pending, token: UUID().uuidString, noteID: noteID, db: db)
                    // Only the complete original + tail fingerprint can establish identity.
                    return Result { try NotesOriginalText.extract(body, origin: pending) }
                }
                uncertainTail = uncertainTail || pending.matchesTail(in: readable)
            }
            // A generated-tail match can signal an edited uncertain write, but cannot prove
            // ownership. Quarantine this read without permanently binding an unrelated ID.
            if uncertainTail { return .failure(NotesReadError.ambiguous) }
            do {
                let text = try NotesOriginalText.extract(body)
                if NotesOriginalText.hasBoundaryEvidence(body) {
                    let tail = String(NotesOriginalText.canonical(readable).dropFirst(NotesOriginalText.canonical(text).count))
                    try storeOrigin(.init(original: text, generated: tail, formatVersion: 1), token: UUID().uuidString, noteID: noteID, db: db)
                }
                return .success(text)
            } catch NotesReadError.ambiguous {
                // Retain a known-but-unseparable identity even if later edits remove all markers.
                try storeOrigin(.init(original: "", formatVersion: 1), token: UUID().uuidString, noteID: noteID, db: db)
                return .failure(NotesReadError.ambiguous)
            }
        }
        return try result.get()
    }

}
