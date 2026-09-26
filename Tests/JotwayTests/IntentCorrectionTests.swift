import GRDB
import XCTest
@testable import Jotway

final class IntentCorrectionTests: XCTestCase {
    func testSaveFetchAndClearRoundTrips() throws {
        XCTAssertEqual(try OperationJSONValue.parse(Data(#"{"x":"\ud83d\ude00","n":1e400}"#.utf8)),
                       .object(["x": .string("😀"), "n": .number("1e400")]))
        for malformed in [#"{"x":"\ud800"}"#, #"{"x":"\udc00"}"#, #"{"x":01}"#, #"{"x":true,"x":false}"#] {
            XCTAssertThrowsError(try OperationJSONValue.parse(Data(malformed.utf8)))
        }
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE grdb_migrations(identifier TEXT NOT NULL PRIMARY KEY);
                INSERT INTO grdb_migrations VALUES ('v1_launcher');
                CREATE TABLE application_usage(path TEXT PRIMARY KEY, openCount INTEGER NOT NULL, lastOpenedAt DATETIME NOT NULL);
                CREATE TABLE intent_feedback(id TEXT PRIMARY KEY, sample BLOB NOT NULL, execution BLOB NOT NULL);
                CREATE TABLE intent_corrections(id TEXT PRIMARY KEY, correctedAt DATETIME NOT NULL, data BLOB NOT NULL);
                CREATE INDEX intent_corrections_recent ON intent_corrections(correctedAt DESC,id DESC);
                INSERT INTO application_usage VALUES ('/Synthetic.app',7,'2026-09-20 00:00:00.000');
                """)
        }
        let sample = Data(#"{"id":"old-1","acceptedAt":800000000.125,"text":"  历史\n正文  ","targetID":"retired-target","action":"future-action","unknown":{"huge":12345678901234567890123456789012345678901234567890e400,"nullable":null},"recognition":{"source":"unrecognized-source"},"draftID":"old-draft","draftRevision":3}"#.utf8)
        let execution = Data(#"{"outcome":"not_started","finished":false,"observedAt":900000000,"unknownResult":[true,"future"]}"#.utf8)
        let correction = Data(#"{"id":"old-2","correctedAt":800000001,"text":"  历史\n正文  ","chosenTargetID":"future-target","chosenLabel":"未来目标","jevTargetID":null,"extraEnum":"preserve-exactly"}"#.utf8)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO intent_feedback VALUES (?,?,?)", arguments: ["old-1",sample,execution])
            try db.execute(sql: "INSERT INTO intent_feedback VALUES (?,?,?)", arguments: ["bad-row",Data("{broken".utf8),execution])
            try db.execute(sql: "INSERT INTO intent_corrections VALUES (?,?,?)", arguments: ["old-2","2026-05-08 00:00:00.000",correction])
        }
        XCTAssertThrowsError(try Database.migrate(queue), "bad historical JSON must roll back the entire migration")
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM intent_feedback"),2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM intent_corrections"),1)
            XCTAssertFalse(try db.tableExists("operation_inputs"))
            XCTAssertEqual(try Data.fetchOne(db, sql: "SELECT sample FROM intent_feedback WHERE id='old-1'"),sample)
        }
        let repaired = Data(#"{"id":"bad-row","text":"another","action":"none","targetID":null}"#.utf8)
        try queue.write { db in
            try db.execute(sql: "UPDATE intent_feedback SET sample = ? WHERE id = 'bad-row'", arguments: [repaired])
        }
        let migrationStartedAt = Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
        try Database.migrate(queue)
        let migrationFinishedAt = Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
        try Database.migrate(queue)
        let store = OperationStore(dbQueue: queue)
        let snapshot = try store.snapshot()
        XCTAssertEqual(snapshot.inputs.count,3)
        XCTAssertEqual(Set(snapshot.inputs.map(\.lineageID)).count,3)
        XCTAssertEqual(snapshot.events.count,3)
        XCTAssertTrue(snapshot.attempts.isEmpty, "migration never invents confirmations or retries")
        XCTAssertEqual(snapshot.contexts.map(\.completeness),[.legacyPartial])
        XCTAssertTrue(snapshot.events.allSatisfy { $0.kind == .legacyObservation && $0.outcome == nil && $0.runID == nil })
        for event in snapshot.events {
            let input = try XCTUnwrap(snapshot.inputs.first { $0.id == event.inputID })
            let restored = try OperationMigration.reconstruct(event: event, input: input)
            if event.legacyID == "old-1" {
                XCTAssertEqual(restored.sample,try OperationJSONValue.parse(sample))
                XCTAssertEqual(restored.execution,try OperationJSONValue.parse(execution))
                XCTAssertTrue(restored.sample?.jsonString.contains("12345678901234567890123456789012345678901234567890e400") == true)
                XCTAssertEqual(input.text,"  历史\n正文  ")
                if case .legacy(let details) = event.details, case .object(let remainder) = details.sample {
                    XCTAssertNil(remainder["text"])
                    XCTAssertNil(remainder["targetID"])
                } else { XCTFail("expected generic legacy object") }
            } else if event.legacyID == "old-2" {
                XCTAssertEqual(restored.data,try OperationJSONValue.parse(correction))
            } else {
                XCTAssertEqual(restored.sample,try OperationJSONValue.parse(repaired))
                XCTAssertGreaterThanOrEqual(input.capturedAt, migrationStartedAt)
                XCTAssertLessThanOrEqual(input.capturedAt, migrationFinishedAt)
                XCTAssertEqual(event.occurredAt, 0, "the original operation time remains unknown")
                if case .legacy(let details) = event.details { XCTAssertFalse(details.occurredAtKnown) }
                else { XCTFail("expected partial legacy observation") }
                let cutoff = migrationFinishedAt - 90 * 86_400_000
                XCTAssertFalse(try store.expiredLineages(before: cutoff).contains(input.lineageID),
                               "unknown-age observations get a normal retention period after migration")
            }
        }
        try queue.read { db in
            XCTAssertFalse(try db.tableExists("intent_feedback"))
            XCTAssertFalse(try db.tableExists("intent_corrections"))
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT openCount FROM application_usage"),7)
            XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
        }
        try store.removeAll()
        XCTAssertTrue(try store.snapshot().events.isEmpty)
        XCTAssertEqual(try LauncherStore(dbQueue: queue).applicationUsage()["/Synthetic.app"]?.openCount,7)
    }
}
