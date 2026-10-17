import Foundation
import GRDB

/// Independent of history indexing and Clear Index. All records are identities, dates and hashes.
actor NotesDailyGroupingStore {
    enum Failure: Error { case stale, invalid, uncertain }
    struct Entry: Codable, Equatable, Sendable {
        let id: String
        let submittedAt: Date
        let timeZoneID: String
        let sequence: Int
    }
    enum Layout: String, Codable, Sendable { case grouped, independent }
    struct Title: Codable, Equatable, Sendable {
        enum State: String, Codable, Sendable { case pending, complete, paused, conflicted, expired, uncertain }
        var state: State
        let firstEntryID: String
        var attemptCount: Int
        var nextAttempt: Date?
        var configurationVersion: String
    }
    struct Snapshot: Codable, Equatable, Sendable {
        let groupID: String
        var noteID: String?
        let scope: NotesDailyScope
        let originalRevision: Int
        let generatedRevision: Int?
        let entries: [Entry]
        let boundary: NotesDailyBoundary
        var conflicted = false
        var layout: Layout = .grouped
        var title: Title? = nil // A legacy snapshot is complete, never retroactively pending.
    }
    struct Pending: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable { case create, append, refresh, title }
        let operationID: String
        let kind: Kind
        let previousBodyHash: String?
        let snapshot: Snapshot
    }

    private let url: URL
    private var queue: DatabaseQueue?

    init(url: URL) { self.url = url }

    private func database() throws -> DatabaseQueue {
        if let queue { return queue }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        // A reopened store may overlap an in-flight refresh from the previous instance.
        // WAL keeps receipt reads independent of writes; serialize competing writers
        // with a bounded wait instead of treating a short SQLite lock as lost storage.
        var configuration = Configuration()
        configuration.journalMode = .wal
        configuration.busyMode = .timeout(5)
        let result = try DatabaseQueue(path: url.path, configuration: configuration)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_daily_grouping") { db in
            try db.execute(sql: """
                CREATE TABLE daily_groups (
                    id TEXT PRIMARY KEY, noteID TEXT UNIQUE, folderID TEXT NOT NULL,
                    day TEXT NOT NULL, timeZoneID TEXT NOT NULL, snapshot BLOB NOT NULL);
                CREATE INDEX daily_scope ON daily_groups(folderID, day);
                CREATE TABLE daily_pending (
                    operationID TEXT PRIMARY KEY, groupID TEXT NOT NULL UNIQUE,
                    folderID TEXT NOT NULL, day TEXT NOT NULL, pending BLOB NOT NULL);
                CREATE TABLE daily_entries (
                    id TEXT PRIMARY KEY, groupID TEXT NOT NULL REFERENCES daily_groups(id),
                    sequence INTEGER NOT NULL, UNIQUE(groupID, sequence));
                """)
        }
        migrator.registerMigration("v2_completion_receipts") { db in
            try db.execute(sql: "ALTER TABLE daily_entries ADD COLUMN notified INTEGER NOT NULL DEFAULT 0")
        }
        try migrator.migrate(result)
        queue = result
        return result
    }

    func snapshots(scope: NotesDailyScope) throws -> [Snapshot] {
        try database().read { db in
            try Data.fetchAll(db, sql: "SELECT snapshot FROM daily_groups WHERE folderID=? AND day=? ORDER BY rowid",
                             arguments: [scope.folderID, scope.day]).map { try JSONDecoder().decode(Snapshot.self, from: $0) }
        }
    }

    func snapshot(groupID: String) throws -> Snapshot? {
        try database().read { try Self.snapshot(groupID: groupID, db: $0) }
    }

    func receipt(entryID: String) throws -> Snapshot? {
        try database().read { db in
            guard let id = try String.fetchOne(db, sql: "SELECT groupID FROM daily_entries WHERE id=?", arguments: [entryID])
            else { return nil }
            return try Self.snapshot(groupID: id, db: db)
        }
    }

    /// Claim once, after confirmed storage. A retry/restart cannot produce a second notice.
    func claimCompletion(entryID: String) throws -> Bool {
        try database().write { db in
            guard try Int.fetchOne(db, sql: "SELECT notified FROM daily_entries WHERE id=?", arguments: [entryID]) == 0
            else { return false }
            try db.execute(sql: "UPDATE daily_entries SET notified=1 WHERE id=?", arguments: [entryID])
            return true
        }
    }

    func pending(scope: NotesDailyScope) throws -> [Pending] {
        try database().read { db in
            try Data.fetchAll(db, sql: "SELECT pending FROM daily_pending WHERE folderID=? AND day=? ORDER BY rowid",
                             arguments: [scope.folderID, scope.day]).map { try JSONDecoder().decode(Pending.self, from: $0) }
        }
    }

    /// Must succeed before an external write. A previous unresolved write cannot be replaced.
    func stage(_ pending: Pending) throws {
        try database().write { db in
            let next = pending.snapshot
            guard !pending.operationID.isEmpty, !next.groupID.isEmpty, !next.entries.isEmpty,
                  !next.conflicted, next.originalRevision == next.entries.count,
                  next.generatedRevision.map({ (1...next.originalRevision).contains($0) }) ?? true,
                  next.entries.map(\.sequence) == Array(0..<next.entries.count),
                  Set(next.entries.map(\.id)).count == next.entries.count,
                  next.boundary.regions.filter({ $0.kind == .original }).compactMap(\.entryID) == next.entries.map(\.id)
            else { throw Failure.invalid }
            if let existing = try Self.pending(operationID: pending.operationID, db: db) {
                guard existing == pending else { throw Failure.stale }
                return
            }
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM daily_pending WHERE groupID=?", arguments: [next.groupID]) == 0
            else { throw Failure.uncertain }
            let previous = try Self.snapshot(groupID: next.groupID, db: db)
            if pending.kind == .create {
                guard previous == nil, next.noteID == nil, pending.previousBodyHash == nil, next.entries.count == 1,
                      next.layout == .independent || next.generatedRevision == nil,
                      next.title?.firstEntryID == next.entries.first?.id || next.title == nil
                else { throw Failure.invalid }
            } else {
                guard let previous, !previous.conflicted, previous.noteID != nil,
                      previous.noteID == next.noteID, previous.scope == next.scope, previous.layout == next.layout,
                      previous.boundary.bodyHash == pending.previousBodyHash else { throw Failure.stale }
                let oldOriginals = previous.boundary.regions.filter { $0.kind == .original }
                let newOriginals = next.boundary.regions.filter { $0.kind == .original }
                if pending.kind == .title {
                    guard let old = previous.title, [.pending, .paused].contains(old.state),
                          next.title?.state == .complete, next.title?.firstEntryID == old.firstEntryID,
                          next.generatedRevision == previous.generatedRevision,
                          previous.boundary.regions.filter({ $0.kind != .title })
                            == next.boundary.regions.filter({ $0.kind != .title })
                    else { throw Failure.invalid }
                } else {
                    guard previous.title == next.title,
                          previous.boundary.regions.first(where: { $0.kind == .title })
                            == next.boundary.regions.first(where: { $0.kind == .title }) else { throw Failure.invalid }
                }
                if pending.kind == .append {
                    guard next.layout == .grouped, next.entries.count == previous.entries.count + 1,
                          Array(next.entries.dropLast()) == previous.entries,
                          Array(newOriginals.dropLast()) == oldOriginals else { throw Failure.invalid }
                } else {
                    guard next.entries == previous.entries, next.originalRevision == previous.originalRevision,
                          newOriginals == oldOriginals
                    else { throw Failure.invalid }
                }
            }
            for entry in next.entries {
                if let owner = try String.fetchOne(db, sql: "SELECT groupID FROM daily_entries WHERE id=?", arguments: [entry.id]),
                   owner != next.groupID { throw Failure.stale }
            }
            // Entry IDs in pending creates/appends also belong to their one unresolved operation.
            for data in try Data.fetchAll(db, sql: "SELECT pending FROM daily_pending") {
                let other = try JSONDecoder().decode(Pending.self, from: data)
                guard Set(other.snapshot.entries.map(\.id)).isDisjoint(with: Set(next.entries.map(\.id)))
                else { throw Failure.uncertain }
            }
            try db.execute(sql: "INSERT INTO daily_pending VALUES (?, ?, ?, ?, ?)", arguments:
                [pending.operationID, next.groupID, next.scope.folderID, next.scope.day, try JSONEncoder().encode(pending)])
        }
    }

    /// Confirmation requires the complete expected version, not a prefix or returned note ID alone.
    @discardableResult
    func confirm(operationID: String, noteID: String, scope: NotesDailyScope, plaintext: String) throws -> Snapshot {
        try database().write { db in
            guard let pending = try Self.pending(operationID: operationID, db: db), !noteID.isEmpty,
                  pending.snapshot.scope == scope, pending.snapshot.boundary.extract(from: plaintext) != nil,
                  pending.snapshot.noteID == nil || pending.snapshot.noteID == noteID else { throw Failure.uncertain }
            var next = pending.snapshot
            if pending.kind != .create {
                guard let previous = try Self.snapshot(groupID: next.groupID, db: db), !previous.conflicted,
                      previous.boundary.bodyHash == pending.previousBodyHash else { throw Failure.stale }
            }
            next.noteID = noteID
            try db.execute(sql: """
                INSERT INTO daily_groups VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET noteID=excluded.noteID, snapshot=excluded.snapshot
                """, arguments: [next.groupID, noteID, scope.folderID, scope.day, scope.timeZoneID, try JSONEncoder().encode(next)])
            for entry in next.entries {
                try db.execute(sql: "INSERT OR IGNORE INTO daily_entries(id, groupID, sequence) VALUES (?, ?, ?)",
                               arguments: [entry.id, next.groupID, entry.sequence])
                guard try String.fetchOne(db, sql: "SELECT groupID FROM daily_entries WHERE id=?", arguments: [entry.id]) == next.groupID
                else { throw Failure.stale }
            }
            try db.execute(sql: "DELETE FROM daily_pending WHERE operationID=?", arguments: [operationID])
            return next
        }
    }

    /// The caller must have proof of non-dispatch/non-write, never merely a timeout.
    func discardUnsent(operationID: String) throws {
        try database().write { db in
            try db.execute(sql: "DELETE FROM daily_pending WHERE operationID=?", arguments: [operationID])
        }
    }

    func markConflicted(groupID: String) throws {
        try database().write { db in
            guard var value = try Self.snapshot(groupID: groupID, db: db) else { return }
            value.conflicted = true
            value.title?.state = .conflicted
            value.title?.nextAttempt = nil
            try db.execute(sql: "UPDATE daily_groups SET snapshot=? WHERE id=?",
                           arguments: [try JSONEncoder().encode(value), groupID])
        }
    }

    /// Compare-and-swap metadata only; never supersedes an unresolved external operation.
    @discardableResult
    func updateTitle(_ title: Title, expected: Snapshot) throws -> Bool {
        try database().write { db in
            guard var current = try Self.snapshot(groupID: expected.groupID, db: db), current == expected,
                  let old = current.title, [.pending, .paused].contains(old.state),
                  title.firstEntryID == old.firstEntryID, title.state != .complete,
                  try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM daily_pending WHERE groupID=?",
                                   arguments: [current.groupID]) == 0 else { return false }
            current.title = title
            try db.execute(sql: "UPDATE daily_groups SET snapshot=? WHERE id=?",
                           arguments: [try JSONEncoder().encode(current), current.groupID])
            return true
        }
    }

    func expireTitles(except scope: NotesDailyScope) throws -> Int {
        try database().write { db in
            var count = 0
            for data in try Data.fetchAll(db, sql: "SELECT snapshot FROM daily_groups WHERE folderID=?", arguments: [scope.folderID]) {
                var value = try JSONDecoder().decode(Snapshot.self, from: data)
                guard value.scope != scope, let title = value.title, [.pending, .paused].contains(title.state) else { continue }
                value.title?.state = .expired; value.title?.nextAttempt = nil
                count += 1
                try db.execute(sql: "UPDATE daily_groups SET snapshot=? WHERE id=?",
                               arguments: [try JSONEncoder().encode(value), value.groupID])
            }
            return count
        }
    }

    private static func snapshot(groupID: String, db: GRDB.Database) throws -> Snapshot? {
        try Data.fetchOne(db, sql: "SELECT snapshot FROM daily_groups WHERE id=?", arguments: [groupID])
            .map { try JSONDecoder().decode(Snapshot.self, from: $0) }
    }

    private static func pending(operationID: String, db: GRDB.Database) throws -> Pending? {
        try Data.fetchOne(db, sql: "SELECT pending FROM daily_pending WHERE operationID=?", arguments: [operationID])
            .map { try JSONDecoder().decode(Pending.self, from: $0) }
    }
}

// Missing fields in pre-title ledgers mean the old grouped layout and a completed title.
extension NotesDailyGroupingStore.Snapshot {
    enum CodingKeys: String, CodingKey {
        case groupID, noteID, scope, originalRevision, generatedRevision, entries, boundary, conflicted, layout, title
    }
    init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        groupID = try data.decode(String.self, forKey: .groupID)
        noteID = try data.decodeIfPresent(String.self, forKey: .noteID)
        scope = try data.decode(NotesDailyScope.self, forKey: .scope)
        originalRevision = try data.decode(Int.self, forKey: .originalRevision)
        generatedRevision = try data.decodeIfPresent(Int.self, forKey: .generatedRevision)
        entries = try data.decode([NotesDailyGroupingStore.Entry].self, forKey: .entries)
        boundary = try data.decode(NotesDailyBoundary.self, forKey: .boundary)
        conflicted = try data.decodeIfPresent(Bool.self, forKey: .conflicted) ?? false
        layout = try data.decodeIfPresent(NotesDailyGroupingStore.Layout.self, forKey: .layout) ?? .grouped
        title = try data.decodeIfPresent(NotesDailyGroupingStore.Title.self, forKey: .title)
    }
}
