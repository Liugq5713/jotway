import Foundation
import CryptoKit
import GRDB
import CSQLiteVec

struct NotesChunk: Equatable, Sendable {
    let ordinal: Int
    let offset: Int // UTF-16 offset in the readable plaintext, before generated regions
    let text: String
    let hash: String

    init(ordinal: Int, offset: Int, text: String) {
        self.ordinal = ordinal
        self.offset = offset
        self.text = text
        self.hash = Self.hash(text)
    }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func split(_ body: NotesSourceBody, origin: NotesOrigin? = nil) throws -> [NotesChunk] {
        try splitOriginal(NotesOriginalText.extract(body, origin: origin))
    }

    static func splitOriginal(_ text: String) throws -> [NotesChunk] {
        var result: [NotesChunk] = []
        var offset = 0
        for paragraph in text.components(separatedBy: "\n\n") {
            var piece = ""
            var pieceOffset = offset
            var characters = 0
            var bytes = 0
            for character in paragraph {
                let characterBytes = String(character).utf8.count
                if characters >= 1_200 || bytes + characterBytes > 4_096 {
                    if !piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        result.append(.init(ordinal: result.count, offset: pieceOffset, text: piece))
                    }
                    pieceOffset += piece.utf16.count
                    piece = ""
                    characters = 0
                    bytes = 0
                }
                guard characterBytes <= 4_096 else { throw NotesHistoryError.tooLarge }
                piece.append(character)
                characters += 1
                bytes += characterBytes
            }
            if !piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.init(ordinal: result.count, offset: pieceOffset, text: piece))
            }
            offset += paragraph.utf16.count + 2
        }
        guard result.count <= 2_000 else { throw NotesHistoryError.tooLarge }
        return result
    }
}

struct NotesHistoryHit: Equatable, Sendable, Identifiable {
    let id: String
    let noteID: String
    let title: String
    let modified: Date
    let text: String
    let ordinal: Int
    let distance: Double
}

/// One recently-modified note assembled from its searchable original chunks, for periodic review.
/// Carries only user original text (generated regions are already excluded at index time).
struct NotesReviewSource: Equatable, Sendable, Identifiable {
    let noteID: String
    let title: String
    let modified: Date
    let text: String
    var id: String { noteID }
}

struct NotesIndexedSource: Sendable {
    let source: NotesSource
    let state: String
    let bodyHash: String
    let attachments: Int
    let chunks: [NotesChunk]
    let vectors: [[Float]]
}

actor NotesIndex {
    struct Status: Sendable {
        var version: Int = 0
        var searchable = 0
        var states: [String: Int] = [:]
        var attachments = 0
        var lastSuccess: Date?
        var checkpoint: String?
    }
    private let url: URL
    private var queue: DatabaseQueue?
    private var profile: NotesEmbeddingProfile

    init(url: URL = StorageLocation.appSupport.appendingPathComponent("notes-index.sqlite"),
         profile: NotesEmbeddingProfile = .init()) {
        self.url = url
        self.profile = profile
    }

    private func database() throws -> DatabaseQueue {
        guard profile.dimension == 1024 else { throw NotesHistoryError.rebuild }
        if let queue { return queue }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            guard sqlite3_vec_init(db.sqliteConnection, nil, nil) == 0 else { throw NotesHistoryError.unavailable }
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
        try migrator.migrate(result)
        try result.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO index_state(id, profile) VALUES (1, ?)", arguments: [profile.identity])
        }
        // Processing-only upgrades invalidate all old vectors before any search, including
        // unchanged ready notes. This never changes the user's started/enabled preferences.
        try result.write { db in
            if let old = try String.fetchOne(db, sql: "SELECT profile FROM index_state WHERE id=1"),
               old != profile.identity {
                let parts = old.split(separator: "|"), current = profile.identity.split(separator: "|")
                if parts.dropLast() == current.dropLast(),
                   let version = parts.last.flatMap({ Int($0) }), version < profile.processingVersion {
                    try db.execute(sql: "DELETE FROM vectors; DELETE FROM chunks;")
                    try db.execute(sql: "UPDATE sources SET state='reprocessing'")
                    try db.execute(sql: "UPDATE index_state SET profile=?, version=version+1, lastSuccess=NULL, checkpoint=NULL WHERE id=1",
                                   arguments: [profile.identity])
                }
            }
        }
        queue = result
        return result
    }

    private func checkProfile(_ db: GRDB.Database) throws {
        guard try String.fetchOne(db, sql: "SELECT profile FROM index_state WHERE id=1") == profile.identity else {
            throw NotesHistoryError.rebuild
        }
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
            else { throw NotesHistoryError.stale }
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
                  (row["targetID"] as String?).map({ $0 == noteID }) ?? true else { throw NotesHistoryError.stale }
            try db.execute(sql: "DELETE FROM daily_origins WHERE noteID=? AND token<>?", arguments: [noteID, token])
            try db.execute(sql: "UPDATE daily_origins SET noteID=?, targetID=? WHERE token=?", arguments: [noteID, noteID, token])
            // A saved revision immediately retires old searchable text; the next permitted sync
            // publishes the new original regions. Clear Index preserves this safety ledger.
            try db.execute(sql: "DELETE FROM vectors WHERE id IN (SELECT id FROM chunks WHERE sourceID=?)", arguments: [noteID])
            try db.execute(sql: "DELETE FROM chunks WHERE sourceID=?", arguments: [noteID])
            try db.execute(sql: "UPDATE sources SET state='reprocessing' WHERE id=?", arguments: [noteID])
            try db.execute(sql: "UPDATE index_state SET version=version+1 WHERE id=1")
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

    /// Extraction and learning legacy provenance share one transaction, before embedding.
    /// Clear Index retains these non-content safety records so a rebuild cannot ingest AI.
    func originalText(noteID: String, body: NotesSourceBody) throws -> String {
        guard body.text.utf8.count <= 2_000_000, body.html.utf8.count <= 4_000_000 else { throw NotesHistoryError.tooLarge }
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
                return .failure(NotesHistoryError.ambiguous)
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
            if uncertainTail { return .failure(NotesHistoryError.ambiguous) }
            do {
                let text = try NotesOriginalText.extract(body)
                if NotesOriginalText.hasBoundaryEvidence(body) {
                    let tail = String(NotesOriginalText.canonical(readable).dropFirst(NotesOriginalText.canonical(text).count))
                    try storeOrigin(.init(original: text, generated: tail, formatVersion: 1), token: UUID().uuidString, noteID: noteID, db: db)
                }
                return .success(text)
            } catch NotesHistoryError.ambiguous {
                // Retain a known-but-unseparable identity even if later edits remove all markers.
                try storeOrigin(.init(original: "", formatVersion: 1), token: UUID().uuidString, noteID: noteID, db: db)
                return .failure(NotesHistoryError.ambiguous)
            }
        }
        return try result.get()
    }

    func status(folders: Set<String>? = nil) throws -> Status {
        try database().read { try status(in: $0, folders: folders) }
    }

    private func status(in db: GRDB.Database, folders: Set<String>?) throws -> Status {
        try checkProfile(db)
        let row = try Row.fetchOne(db, sql: "SELECT * FROM index_state WHERE id=1")!
        var status = Status(version: row["version"])
        status.lastSuccess = (row["lastSuccess"] as Double?).map(Date.init(timeIntervalSince1970:))
        status.checkpoint = row["checkpoint"]
        let filter: String
        let arguments: StatementArguments
        if let folders {
            filter = " WHERE folderID IN (" + folders.map { _ in "?" }.joined(separator: ",") + ")"
            arguments = StatementArguments(folders.sorted())
        } else { filter = ""; arguments = [] }
        status.searchable = try Int.fetchOne(db, sql: """
            SELECT count(DISTINCT sourceID) FROM chunks JOIN sources ON sources.id=chunks.sourceID\(filter)
            """, arguments: arguments) ?? 0
        status.attachments = try Int.fetchOne(db, sql: "SELECT coalesce(sum(attachments),0) FROM sources" + filter,
                                              arguments: arguments) ?? 0
        for state in try Row.fetchAll(db, sql: "SELECT state, count(*) AS count FROM sources" + filter + " GROUP BY state",
                                      arguments: arguments) {
            status.states[state["state"]] = state["count"]
        }
        return status
    }

    func isCurrent(_ source: NotesSource) throws -> Bool {
        try database().read { db in
            try checkProfile(db)
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM sources WHERE id=?", arguments: [source.id]) else { return false }
            return (row["modified"] as Double) == source.modified.timeIntervalSince1970
                && (row["folderID"] as String) == source.folderID && (row["title"] as String) == source.title
                && (row["shared"] as Bool) == source.shared && !source.locked
                && (row["state"] as String) == "ready"
                && (row["processingVersion"] as Int) == profile.processingVersion
        }
    }

    func cachedVector(hash: String) throws -> [Float]? {
        try database().read { db in
            try checkProfile(db)
            guard let data = try Data.fetchOne(db, sql: """
                SELECT v.embedding FROM chunks c JOIN vectors v ON v.id=c.id WHERE c.hash=? LIMIT 1
                """, arguments: [hash]) else { return nil }
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
    }

    /// Ready notes modified since `cutoff` (seconds since 1970), newest first, each note's original
    /// chunks concatenated in order. `limit` bounds the note count; `charactersPerNote` bounds text.
    func recentSources(since cutoff: Double, folders: Set<String>?, limit: Int,
                       charactersPerNote: Int = 4_000) throws -> [NotesReviewSource] {
        try database().read { db in
            try checkProfile(db)
            var sql = """
                SELECT s.id AS sourceID, s.title AS title, s.modified AS modified, c.text AS text
                FROM sources s JOIN chunks c ON c.sourceID = s.id
                WHERE s.modified >= ? AND s.state = 'ready'
                """
            var arguments: StatementArguments = [cutoff]
            if let folders {
                guard !folders.isEmpty else { return [] }
                sql += " AND s.folderID IN (" + folders.map { _ in "?" }.joined(separator: ",") + ")"
                arguments += StatementArguments(folders.sorted())
            }
            sql += " ORDER BY s.modified DESC, s.id, c.ordinal"
            var order: [String] = []
            var titles: [String: String] = [:]
            var modified: [String: Double] = [:]
            var pieces: [String: [String]] = [:]
            for row in try Row.fetchAll(db, sql: sql, arguments: arguments) {
                let id: String = row["sourceID"]
                if pieces[id] == nil {
                    guard order.count < limit else { continue }
                    order.append(id)
                    titles[id] = row["title"]
                    modified[id] = row["modified"]
                    pieces[id] = []
                }
                pieces[id]?.append(row["text"])
            }
            return order.map { id in
                NotesReviewSource(noteID: id, title: String((titles[id] ?? "").prefix(200)),
                    modified: Date(timeIntervalSince1970: modified[id] ?? 0),
                    text: String((pieces[id] ?? []).joined(separator: "\n\n").prefix(charactersPerNote)))
            }
        }
    }

    /// A completed batch is one transaction and one revision. No source can expose half its chunks.
    func publish(_ entries: [NotesIndexedSource], checkpoint: String) throws {
        try Task.checkCancellation()
        try database().write { db in
            try checkProfile(db)
            for entry in entries {
                try Task.checkCancellation()
                guard entry.chunks.count == entry.vectors.count,
                      entry.vectors.allSatisfy({ ModelEmbeddingInvocation.valid($0) }) else { throw NotesHistoryError.response }
                let source = entry.source
                try deleteChunks(source.id, db: db)
                try db.execute(sql: """
                    INSERT OR REPLACE INTO sources VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [source.id, source.folderID, source.title, source.created.timeIntervalSince1970,
                                     source.modified.timeIntervalSince1970, source.shared, entry.state, entry.bodyHash, entry.attachments, profile.processingVersion])
                for (chunk, vector) in zip(entry.chunks, entry.vectors) {
                    try db.execute(sql: "INSERT INTO chunks(sourceID, ordinal, offset, text, hash) VALUES (?, ?, ?, ?, ?)",
                                   arguments: [source.id, chunk.ordinal, chunk.offset, chunk.text, chunk.hash])
                    let id = db.lastInsertedRowID
                    let data = vector.withUnsafeBytes { Data($0) }
                    try db.execute(sql: "INSERT INTO vectors(id, embedding, folder_id) VALUES (?, ?, ?)",
                                   arguments: [id, data, source.folderID])
                }
            }
            try db.execute(sql: "UPDATE index_state SET version=version+1, checkpoint=? WHERE id=1", arguments: [checkpoint])
        }
    }

    /// Call only after every metadata list in these folders completed. Absent accounts/folders
    /// are deliberately not deletion evidence. A body failure still keeps its source identity.
    func reconcile(_ idsByFolder: [String: Set<String>], successful: Bool) throws {
        try Task.checkCancellation()
        try database().write { db in
            try checkProfile(db)
            let allSeen = Set(idsByFolder.values.flatMap { $0 })
            for (folder, _) in idsByFolder {
                let ids = try String.fetchAll(db, sql: "SELECT id FROM sources WHERE folderID=?", arguments: [folder])
                for id in ids where !allSeen.contains(id) {
                    try deleteChunks(id, db: db)
                    try db.execute(sql: "DELETE FROM sources WHERE id=?", arguments: [id])
                }
            }
            try db.execute(sql: "UPDATE index_state SET version=version+1, checkpoint=NULL WHERE id=1")
            if successful {
                try db.execute(sql: "UPDATE index_state SET lastSuccess=? WHERE id=1", arguments: [Date().timeIntervalSince1970])
            }
        }
    }

    private func deleteChunks(_ id: String, db: GRDB.Database) throws {
        let ids = try Int64.fetchAll(db, sql: "SELECT id FROM chunks WHERE sourceID=?", arguments: [id])
        for chunkID in ids { try db.execute(sql: "DELETE FROM vectors WHERE id=?", arguments: [chunkID]) }
        try db.execute(sql: "DELETE FROM chunks WHERE sourceID=?", arguments: [id])
    }

    func clear(rebuildingWith replacement: NotesEmbeddingProfile? = nil) throws {
        let next = replacement ?? profile
        guard next.dimension == 1024 else { throw NotesHistoryError.rebuild }
        try database().write { db in
            try db.execute(sql: "DELETE FROM vectors; DELETE FROM chunks; DELETE FROM sources;")
            try db.execute(sql: "UPDATE index_state SET profile=?, version=version+1, checkpoint=NULL, lastSuccess=NULL WHERE id=1",
                           arguments: [next.identity])
        }
        profile = next
        // Derived plaintext should not linger in free pages after an explicit clear.
        try database().writeWithoutTransaction { try $0.execute(sql: "VACUUM") }
    }

    func search(vector: [Float], folders: Set<String>?, version: Int, text original: String,
                excludingNoteID: String? = nil) throws -> NotesRetrievalResult {
        try Task.checkCancellation()
        guard ModelEmbeddingInvocation.valid(vector) else { throw NotesHistoryError.response }
        return try database().read { db in
            try checkProfile(db)
            guard try Int.fetchOne(db, sql: "SELECT version FROM index_state WHERE id=1") == version else {
                throw NotesHistoryError.stale
            }
            let data = vector.withUnsafeBytes { Data($0) }
            var rows: [Row] = []
            // Per-folder exact top-k then merge is scope-correct, including rare folders.
            let scopes: [String?] = folders.map { $0.sorted().map(Optional.some) } ?? [nil]
            for folder in scopes {
                try Task.checkCancellation()
                let filter = folder == nil ? "" : " AND folder_id = ?"
                var arguments: StatementArguments = [data]
                if let folder { arguments += [folder] }
                rows += try Row.fetchAll(db, sql: """
                    WITH nearest AS (SELECT id, distance FROM vectors WHERE embedding MATCH ? AND k=40\(filter))
                    SELECT c.*, s.title, s.modified, n.distance FROM nearest n
                    JOIN chunks c ON c.id=n.id JOIN sources s ON s.id=c.sourceID ORDER BY n.distance
                    """, arguments: arguments)
            }
            var eligible: [NotesHistoryHit] = []
            var notes = Set<String>()
            var texts = Set<String>()
            var counts = NotesRetrievalResult.Counts(rawChunkCount: rows.count)
            let ordered = rows.sorted {
                let a: Double = $0["distance"], b: Double = $1["distance"]
                if a != b { return a < b }
                return ($0["id"] as Int64) < ($1["id"] as Int64)
            }
            for row in ordered {
                try Task.checkCancellation()
                let distance: Double = row["distance"]
                guard distance.isFinite, distance <= 0.35 else { continue }
                counts.thresholdChunkCount += 1
                let text = String((row["text"] as String).prefix(400))
                guard NotesEvidence.hasEvidence(text), !NotesEvidence.overlaps(text, original) else { continue }
                let noteID: String = row["sourceID"]
                guard noteID != excludingNoteID else { continue }
                let comparison = NotesEvidence.comparisonText(text)
                guard !notes.contains(noteID), !texts.contains(comparison) else { continue }
                notes.insert(noteID); texts.insert(comparison)
                eligible.append(.init(id: String(row["id"] as Int64), noteID: noteID,
                    title: String((row["title"] as String).prefix(200)),
                    modified: Date(timeIntervalSince1970: row["modified"]), text: text,
                    ordinal: row["ordinal"], distance: distance))
            }
            counts.eligibleSourceCount = eligible.count
            var hits: [NotesHistoryHit] = []
            for hit in eligible {
                guard counts.candidateBytes + hit.text.utf8.count <= NotesRetrievalResult.maximumBytes else { continue }
                hits.append(hit)
                counts.candidateBytes += hit.text.utf8.count
                if hits.count == NotesRetrievalResult.maximumCandidates { break }
            }
            counts.candidateCount = hits.count
            let state = try status(in: db, folders: folders)
            let pending = (state.states["pending"] ?? 0) + (state.states["reprocessing"] ?? 0)
            let excluded = state.states.filter { !["ready", "pending", "reprocessing", "failed"].contains($0.key) }
                .values.reduce(0, +)
            return NotesRetrievalResult(hits: hits, counts: counts,
                coverage: .init(searchable: state.searchable, pending: pending,
                    failed: state.states["failed"] ?? 0, excluded: excluded, hasSuccessfulSync: state.lastSuccess != nil),
                version: state.version)
        }
    }
}

struct NotesRetriever: Sendable {
    let index: NotesIndex
    var client: ModelEmbeddingInvocation
    let folders: Set<String>?
    let version: Int

    func search(_ text: String, excludingNoteID: String? = nil) async throws -> NotesRetrievalResult {
        try await client.validate()
        try await index.validateProfile(client.profile)
        let bounded = String(text.prefix(4_000))
        let vectors = try await client.embed([bounded], type: .query)
        let hits = try await index.search(vector: vectors[0], folders: folders, version: version,
                                          text: text, excludingNoteID: excludingNoteID)
        try await client.validate()
        guard try await index.status(folders: folders).version == version else { throw NotesHistoryError.stale }
        return hits
    }
}

extension NotesIndex {
    func validateProfile(_ incoming: NotesEmbeddingProfile) throws {
        guard incoming.dimension == 1024 else { throw NotesHistoryError.rebuild }
        if incoming.identity != profile.identity {
            // An empty, never-indexed store may already contain text-free save origins.
            // Keep those origins while adopting the user's first service configuration.
            try database().write { db in
                guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sources") == 0,
                      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chunks") == 0,
                      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM vectors") == 0 else {
                    throw NotesHistoryError.rebuild
                }
                try db.execute(sql: "UPDATE index_state SET profile=?, version=version+1, checkpoint=NULL, lastSuccess=NULL WHERE id=1",
                               arguments: [incoming.identity])
            }
            profile = incoming
        }
        try database().read { try checkProfile($0) }
    }
}
