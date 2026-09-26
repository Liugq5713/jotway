import Foundation
import GRDB

enum OperationStoreError: Error, Equatable {
    case invalid(String)
    case conflict(String)
    case missingReference(String)
}

/// Synchronous transaction boundary. OperationRecorder owns scheduling, generations and completeness.
struct OperationStore: Sendable {
    struct Statistics: Sendable {
        let inputCount: Int
        let contextCount: Int
        let attemptCount: Int
        let eventCount: Int
        /// Logical column payload: UTF-8 text/JSON and eight bytes per stored integer.
        /// Excludes SQLite pages, indexes, free space, and JSON export wrappers.
        let storedBytes: Int64
    }

    let dbQueue: DatabaseQueue
    init(dbQueue: DatabaseQueue) { self.dbQueue = dbQueue }
    init(repository: LauncherStore) { dbQueue = repository.dbQueue }

    @discardableResult
    func capture(input: OperationInput, context: OperationContext, event: OperationEvent) throws -> Bool {
        try dbQueue.write { db in
            guard event.kind == .inputCaptured, event.inputID == input.id, event.contextID == context.id else {
                throw OperationStoreError.invalid("capture_identity")
            }
            try Self.insert(input, in: db)
            try Self.insert(context, in: db)
            return try Self.append(event, in: db)
        }
    }

    func ensureContext(_ context: OperationContext) throws {
        try dbQueue.write { db in try Self.insert(context, in: db) }
    }

    @discardableResult
    func confirm(attempt: OperationAttempt, event: OperationEvent) throws -> Bool {
        try dbQueue.write { db in
            guard event.kind == .confirmRequested, event.attemptID == attempt.id,
                  event.inputID == attempt.inputID, event.contextID == attempt.contextID else {
                throw OperationStoreError.invalid("confirmation_identity")
            }
            if let previous = try Self.event(event.id, in: db) {
                try Self.identical(event, previous)
                guard try Self.attempt(attempt.id, in: db) == attempt else {
                    throw OperationStoreError.conflict("attempt")
                }
                return false
            }
            try Self.validate(attempt, in: db)
            try db.execute(sql: """
                INSERT INTO operation_attempts
                (id,input_id,context_id,target_kind,target_id,route_source,selection_origin,confirmation_source,
                 decision_event_id,first_choice_event_id,retry_of_attempt_id) VALUES (?,?,?,?,?,?,?,?,?,?,?)
                """, arguments: [attempt.id, attempt.inputID, attempt.contextID, attempt.targetKind.rawValue,
                    attempt.targetID, attempt.routeSource.rawValue, attempt.selectionOrigin.rawValue,
                    attempt.confirmationSource.rawValue, attempt.decisionEventID, attempt.firstChoiceEventID,
                    attempt.retryOfAttemptID])
            return try Self.append(event, in: db)
        }
    }

    @discardableResult
    func append(_ event: OperationEvent) throws -> Bool {
        try dbQueue.write { db in try Self.append(event, in: db) }
    }

    func snapshot() throws -> OperationSnapshot {
        try dbQueue.read { db in try Self.snapshot(in: db) }
    }

    func statistics() throws -> Statistics {
        try dbQueue.read { db in try Self.statistics(in: db) }
    }

    func exportSnapshot() throws -> (records: OperationSnapshot, statistics: Statistics) {
        try dbQueue.read { db in
            (try Self.snapshot(in: db), try Self.statistics(in: db))
        }
    }

    private static func snapshot(in db: GRDB.Database) throws -> OperationSnapshot {
        .init(inputs: try Row.fetchAll(db, sql: "SELECT * FROM operation_inputs ORDER BY captured_at,id").map(Self.input),
              contexts: try Row.fetchAll(db, sql: "SELECT * FROM operation_contexts ORDER BY id").map(Self.context),
              attempts: try Row.fetchAll(db, sql: "SELECT * FROM operation_attempts ORDER BY id").map(Self.attempt),
              events: try Row.fetchAll(db, sql: "SELECT * FROM operation_events ORDER BY sequence").map(Self.event))
    }

    private static func statistics(in db: GRDB.Database) throws -> Statistics {
        guard let row = try Row.fetchOne(db, sql: statisticsSQL) else {
            throw OperationStoreError.invalid("missing_statistics")
        }
        return .init(inputCount: row["input_count"], contextCount: row["context_count"],
                     attemptCount: row["attempt_count"], eventCount: row["event_count"],
                     storedBytes: row["stored_bytes"])
    }

    private static let statisticsSQL: String = {
        // All identifiers below are fixed schema names. Return one aggregate row without
        // materializing any input body or decoding event/configuration JSON in Swift.
        func bytes(text: [String], integers: [String] = [], cachedBytes: [String] = []) -> String {
            (text.map { "COALESCE(length(CAST(\($0) AS BLOB)), 0)" }
                + integers.map { "CASE WHEN \($0) IS NULL THEN 0 ELSE 8 END" }
                + cachedBytes).joined(separator: " + ")
        }
        let input = bytes(text: ["id", "lineage_id"],
                          integers: ["input_version", "captured_at", "utf8_bytes"], cachedBytes: ["utf8_bytes"])
        let context = bytes(text: ["id", "completeness", "app_version", "app_build", "rule_version",
                                   "requested_model", "configuration_json"], integers: ["captured_at", "schema_version"])
        let attempt = bytes(text: ["id", "input_id", "context_id", "target_kind", "target_id", "route_source",
                                   "selection_origin", "confirmation_source", "decision_event_id", "first_choice_event_id",
                                   "retry_of_attempt_id"])
        let event = bytes(text: ["id", "input_id", "context_id", "run_id", "kind", "attempt_id", "request_id",
                                 "target_kind", "target_id", "route_source", "outcome", "reason_code", "details_json",
                                 "legacy_source", "legacy_id"],
                          integers: ["sequence", "occurred_at", "duration_ms", "detail_version"])
        return """
            WITH i AS (SELECT COUNT(*) AS n, COALESCE(SUM(\(input)), 0) AS bytes FROM operation_inputs),
                 c AS (SELECT COUNT(*) AS n, COALESCE(SUM(\(context)), 0) AS bytes FROM operation_contexts),
                 a AS (SELECT COUNT(*) AS n, COALESCE(SUM(\(attempt)), 0) AS bytes FROM operation_attempts),
                 e AS (SELECT COUNT(*) AS n, COALESCE(SUM(\(event)), 0) AS bytes FROM operation_events)
            SELECT i.n AS input_count, c.n AS context_count, a.n AS attempt_count, e.n AS event_count,
                   i.bytes + c.bytes + a.bytes + e.bytes AS stored_bytes
            FROM i CROSS JOIN c CROSS JOIN a CROSS JOIN e
            """
    }()

    func removeAll() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM operation_inputs; DELETE FROM operation_contexts;")
        }
    }

    func expiredLineages(before: Int64) throws -> Set<String> {
        try dbQueue.read { db in
            Set(try String.fetchAll(db, sql: """
                SELECT i.lineage_id FROM operation_inputs i
                LEFT JOIN operation_events e ON e.input_id = i.id
                GROUP BY i.lineage_id
                HAVING MAX(MAX(i.captured_at, COALESCE(e.occurred_at, i.captured_at))) < ?
                """, arguments: [before]))
        }
    }

    @discardableResult
    func expire(before: Int64, excludingLineages: Set<String> = []) throws -> Set<String> {
        try dbQueue.write { db in
            let candidates = try String.fetchAll(db, sql: """
                SELECT i.lineage_id FROM operation_inputs i
                LEFT JOIN operation_events e ON e.input_id = i.id
                GROUP BY i.lineage_id
                HAVING MAX(MAX(i.captured_at, COALESCE(e.occurred_at, i.captured_at))) < ?
                """, arguments: [before])
            return try Self.expire(Set(candidates).subtracting(excludingLineages), in: db)
        }
    }

    @discardableResult
    func expire(lineages: Set<String>) throws -> Set<String> {
        try dbQueue.write { db in try Self.expire(lineages, in: db) }
    }

    private static func expire(_ lineages: Set<String>, in db: GRDB.Database) throws -> Set<String> {
        var deleted = Set<String>()
        for lineage in lineages {
            try db.execute(sql: "DELETE FROM operation_inputs WHERE lineage_id = ?", arguments: [lineage])
            if db.changesCount > 0 { deleted.insert(lineage) }
        }
        try db.execute(sql: """
            DELETE FROM operation_contexts WHERE id NOT IN (
                SELECT context_id FROM operation_events UNION SELECT context_id FROM operation_attempts
            )
            """)
        return deleted
    }

    static func insert(_ input: OperationInput, in db: GRDB.Database) throws {
        guard !input.id.isEmpty, !input.lineageID.isEmpty, input.inputVersion >= 0 else {
            throw OperationStoreError.invalid("input")
        }
        if let row = try Row.fetchOne(db, sql: "SELECT * FROM operation_inputs WHERE id = ? OR (lineage_id = ? AND input_version = ?)",
                                     arguments: [input.id, input.lineageID, input.inputVersion]) {
            let previous = Self.input(row)
            guard previous.id == input.id, previous.lineageID == input.lineageID,
                  previous.inputVersion == input.inputVersion, previous.text == input.text else {
                throw OperationStoreError.conflict("input")
            }
            return
        }
        try db.execute(sql: "INSERT INTO operation_inputs(id,lineage_id,input_version,captured_at,text,utf8_bytes) VALUES (?,?,?,?,?,?)",
                       arguments: [input.id, input.lineageID, input.inputVersion, input.capturedAt, input.text, input.utf8Bytes])
    }

    static func insert(_ context: OperationContext, in db: GRDB.Database) throws {
        let validated = try OperationContext(capturedAt: context.capturedAt, completeness: context.completeness,
            appVersion: context.appVersion, appBuild: context.appBuild, ruleVersion: context.ruleVersion,
            requestedModel: context.requestedModel, configuration: context.configuration)
        guard context.schemaVersion == 1, validated.id == context.id else {
            throw OperationStoreError.invalid("context_digest")
        }
        if let row = try Row.fetchOne(db, sql: "SELECT * FROM operation_contexts WHERE id = ?", arguments: [context.id]) {
            guard try Self.context(row).hasSameContent(as: context) else { throw OperationStoreError.conflict("context") }
            return
        }
        let json = String(decoding: try operationJSON(context.configuration), as: UTF8.self)
        try db.execute(sql: """
            INSERT INTO operation_contexts(id,captured_at,schema_version,completeness,app_version,app_build,rule_version,
                                           requested_model,configuration_json) VALUES (?,?,?,?,?,?,?,?,?)
            """, arguments: [context.id, context.capturedAt, context.schemaVersion, context.completeness.rawValue,
                context.appVersion, context.appBuild, context.ruleVersion, context.requestedModel, json])
    }

    @discardableResult
    static func append(_ event: OperationEvent, in db: GRDB.Database) throws -> Bool {
        if let previous = try Self.event(event.id, in: db) { try identical(event, previous); return false }
        try validate(event, in: db)
        let details = String(decoding: try operationJSON(event.details), as: UTF8.self)
        try db.execute(sql: """
            INSERT INTO operation_events
            (id,input_id,context_id,run_id,occurred_at,kind,attempt_id,request_id,target_kind,target_id,
             route_source,outcome,reason_code,duration_ms,detail_version,details_json,legacy_source,legacy_id)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, arguments: [event.id, event.inputID, event.contextID, event.runID, event.occurredAt,
                event.kind.rawValue, event.attemptID, event.requestID, event.targetKind?.rawValue, event.targetID,
                event.routeSource?.rawValue, event.outcome?.rawValue, event.reasonCode, event.durationMS,
                event.detailVersion, details, event.legacySource?.rawValue, event.legacyID])
        return true
    }

    private static func identical(_ incoming: OperationEvent, _ stored: OperationEvent) throws {
        var value = incoming
        value.sequence = stored.sequence
        guard value == stored else { throw OperationStoreError.conflict("event") }
    }

    private static func validate(_ attempt: OperationAttempt, in db: GRDB.Database) throws {
        guard !attempt.id.isEmpty, !attempt.targetID.isEmpty,
              [.action, .application].contains(attempt.targetKind) else { throw OperationStoreError.invalid("attempt") }
        guard try Row.fetchOne(db, sql: "SELECT id FROM operation_inputs WHERE id = ?", arguments: [attempt.inputID]) != nil else {
            throw OperationStoreError.missingReference("input")
        }
        if let id = attempt.decisionEventID {
            guard let decision = try event(id, in: db), decision.kind == .routePresented,
                  decision.inputID == attempt.inputID, decision.targetKind == attempt.targetKind,
                  decision.targetID == attempt.targetID, decision.routeSource == attempt.routeSource,
                  decision.outcome == .available else { throw OperationStoreError.invalid("decision_reference") }
        }
        if attempt.selectionOrigin == .userChoice, attempt.firstChoiceEventID == nil {
            throw OperationStoreError.invalid("missing_choice_reference")
        }
        if let id = attempt.firstChoiceEventID {
            guard let choice = try event(id, in: db), choice.kind == .targetSelected,
                  choice.inputID == attempt.inputID, case .selection(let detail) = choice.details,
                  detail.selectionOrigin == .userChoice else { throw OperationStoreError.invalid("choice_reference") }
            let choices = try Row.fetchAll(db, sql: "SELECT * FROM operation_events WHERE input_id = ? AND kind = 'target_selected' ORDER BY sequence",
                                          arguments: [attempt.inputID]).map(Self.event)
            let first = choices.first { event in
                if case .selection(let details) = event.details { return details.selectionOrigin == .userChoice }
                return false
            }
            guard first?.id == id else { throw OperationStoreError.invalid("first_choice_reference") }
        }
        if let id = attempt.retryOfAttemptID {
            guard id != attempt.id, let earlier = try Self.attempt(id, in: db),
                  let oldLineage = try String.fetchOne(db, sql: "SELECT lineage_id FROM operation_inputs WHERE id = ?", arguments: [earlier.inputID]),
                  let newLineage = try String.fetchOne(db, sql: "SELECT lineage_id FROM operation_inputs WHERE id = ?", arguments: [attempt.inputID]),
                  oldLineage == newLineage else { throw OperationStoreError.invalid("retry_reference") }
        }
    }

    private static func validate(_ event: OperationEvent, in db: GRDB.Database) throws {
        guard !event.id.isEmpty, event.detailVersion == 1, (event.durationMS ?? 0) >= 0,
              (event.targetKind == nil) == (event.targetID == nil), event.targetID?.isEmpty != true,
              event.requestID?.isEmpty != true else { throw OperationStoreError.invalid("event") }
        if let reason = event.reasonCode {
            guard !reason.isEmpty, reason.utf8.count <= 80,
                  reason.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }) else {
                throw OperationStoreError.invalid("reason_code")
            }
        }
        guard try Row.fetchOne(db, sql: "SELECT id FROM operation_inputs WHERE id = ?", arguments: [event.inputID]) != nil else {
            throw OperationStoreError.missingReference("input")
        }
        if event.kind == .legacyObservation {
            guard event.runID == nil, event.attemptID == nil, event.legacySource != nil,
                  event.legacyID?.isEmpty == false, case .legacy = event.details else {
                throw OperationStoreError.invalid("legacy")
            }
            return
        }
        guard event.runID?.isEmpty == false, event.legacySource == nil, event.legacyID == nil else {
            throw OperationStoreError.invalid("run")
        }
        let recognitionKinds: Set<OperationEventKind> = [.recognitionStarted, .recognitionFinished]
        if !recognitionKinds.contains(event.kind), event.requestID != nil {
            throw OperationStoreError.invalid("unexpected_request")
        }
        let targetKinds: Set<OperationEventKind> = [.recognitionFinished, .routePresented, .targetSelected,
                                                  .setupStarted, .setupFinished, .confirmationBlocked]
        if !targetKinds.contains(event.kind), event.targetKind != nil || event.routeSource != nil {
            throw OperationStoreError.invalid("unexpected_target")
        }
        if ![OperationEventKind.recognitionFinished, .executionFinished, .setupFinished].contains(event.kind), event.durationMS != nil {
            throw OperationStoreError.invalid("unexpected_duration")
        }
        let reasonKinds: Set<OperationEventKind> = [.recognitionFinished, .routePresented, .confirmationBlocked,
                                                  .submissionRejected, .executionFinished, .setupFinished]
        if !reasonKinds.contains(event.kind), event.reasonCode != nil {
            throw OperationStoreError.invalid("unexpected_reason")
        }
        let attemptKinds: Set<OperationEventKind> = [.confirmRequested, .submissionAccepted, .submissionRejected, .executionFinished]
        if attemptKinds.contains(event.kind) {
            guard let id = event.attemptID, let attempt = try Self.attempt(id, in: db),
                  attempt.inputID == event.inputID, attempt.contextID == event.contextID,
                  event.targetKind == nil, event.routeSource == nil else {
                throw OperationStoreError.invalid("attempt_event")
            }
            if event.kind != .confirmRequested {
                guard try Int.fetchOne(db, sql: "SELECT 1 FROM operation_events WHERE attempt_id = ? AND kind = 'confirm_requested'", arguments: [id]) == 1 else {
                    throw OperationStoreError.invalid("confirmation_order")
                }
            }
            if event.kind == .executionFinished {
                guard try Int.fetchOne(db, sql: "SELECT 1 FROM operation_events WHERE attempt_id = ? AND kind = 'submission_accepted'", arguments: [id]) == 1 else {
                    throw OperationStoreError.invalid("execution_order")
                }
            }
        } else if event.attemptID != nil { throw OperationStoreError.invalid("unexpected_attempt") }
        switch (event.kind, event.details) {
        case (.inputCaptured, .capture): try outcome(event, allowed: [])
        case (.panelOpened, .panel(let details)), (.panelHidden, .panel(let details)):
            guard !details.presentationID.isEmpty else { throw OperationStoreError.invalid("panel_identity") }
            try outcome(event, allowed: [])
        case (.recognitionStarted, .recognition(let details)), (.recognitionFinished, .recognition(let details)):
            for option in details.options {
                guard !option.id.isEmpty, [option.score, option.confidence].compactMap({ $0 }).allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                    throw OperationStoreError.invalid("recognition_option")
                }
            }
            for candidate in details.candidates {
                guard !candidate.id.isEmpty, (candidate.rank ?? 0) >= 0, (candidate.openCount ?? 0) >= 0,
                      candidate.score.map({ $0.isFinite }) ?? true else {
                    throw OperationStoreError.invalid("recognition_candidate")
                }
            }
            guard let request = event.requestID else { throw OperationStoreError.invalid("recognition_request") }
            if event.kind == .recognitionStarted { try outcome(event, allowed: []) }
            else {
                try outcome(event, allowed: [.suggested, .noSuggestion, .failed, .cancelled, .stale], required: true)
                guard let started = try Row.fetchOne(db, sql: "SELECT * FROM operation_events WHERE request_id = ? AND kind = 'recognition_started'", arguments: [request]),
                      started["input_id"] as String == event.inputID, started["context_id"] as String == event.contextID else {
                    throw OperationStoreError.invalid("recognition_snapshot")
                }
            }
        case (.routePresented, .route(let details)):
            guard !details.presentationID.isEmpty else { throw OperationStoreError.invalid("presentation_identity") }
            try outcome(event, allowed: [.available, .setup, .unavailable], required: true)
            if event.outcome == .available {
                guard event.targetKind == .action || event.targetKind == .application, event.routeSource != nil else {
                    throw OperationStoreError.invalid("presented_target")
                }
            }
            if event.outcome == .setup, event.targetKind != .setup { throw OperationStoreError.invalid("presented_setup") }
        case (.targetSelected, .selection(let details)):
            guard event.targetKind != nil, event.routeSource == .explicit else { throw OperationStoreError.invalid("selected_target") }
            guard details.selectionOrigin != .automatic,
                  (details.selectionOrigin == .setupCompletion) == (details.trigger == .setupCompletion) else {
                throw OperationStoreError.invalid("selection_origin")
            }
            if let id = details.previousPresentedEventID {
                guard let previous = try Self.event(id, in: db), previous.kind == .routePresented,
                      previous.inputID == event.inputID else { throw OperationStoreError.invalid("previous_presentation") }
            }
            try outcome(event, allowed: [])
        case (.setupStarted, .setup(let details)), (.setupFinished, .setup(let details)):
            guard event.targetKind == .setup, !details.setupID.isEmpty else { throw OperationStoreError.invalid("setup_target") }
            if event.kind == .setupStarted { try outcome(event, allowed: []) }
            else {
                try outcome(event, allowed: [.completed, .cancelled, .failed], required: true)
                let related = try Row.fetchAll(db, sql: "SELECT * FROM operation_events WHERE input_id = ? AND kind IN ('setup_started','setup_finished') ORDER BY sequence",
                                               arguments: [event.inputID]).map(Self.event).filter {
                    if case .setup(let previous) = $0.details { return previous.setupID == details.setupID }
                    return false
                }
                guard related.count == 1, let start = related.first, start.kind == .setupStarted,
                      start.contextID == event.contextID, start.runID == event.runID,
                      start.targetID == event.targetID else { throw OperationStoreError.invalid("setup_order") }
            }
        case (.confirmationBlocked, .confirmation):
            guard event.reasonCode != nil else { throw OperationStoreError.invalid("blocked_reason") }
            try outcome(event, allowed: [.unavailable, .failed])
        case (.confirmRequested, .confirmation): try outcome(event, allowed: [])
        case (.submissionAccepted, .submission): try outcome(event, allowed: [.accepted])
        case (.submissionRejected, .submission):
            guard event.reasonCode != nil else { throw OperationStoreError.invalid("rejected_reason") }
            try outcome(event, allowed: [.failed, .unavailable])
        case (.executionFinished, .execution):
            try outcome(event, allowed: [.created, .opened, .prefilled, .accepted, .failed, .unknown], required: true)
        case (.draftRestored, .restoration(let details)):
            guard !details.sourceLineageID.isEmpty else { throw OperationStoreError.invalid("restore_source") }
            try outcome(event, allowed: [])
        case (.draftCleared, .clear): try outcome(event, allowed: [])
        default: throw OperationStoreError.invalid("event_details")
        }
    }

    private static func outcome(_ event: OperationEvent, allowed: Set<OperationEventOutcome>, required: Bool = false) throws {
        if let value = event.outcome {
            guard allowed.contains(value) else { throw OperationStoreError.invalid("outcome") }
        } else if required { throw OperationStoreError.invalid("missing_outcome") }
    }

    private static func event(_ id: String, in db: GRDB.Database) throws -> OperationEvent? {
        try Row.fetchOne(db, sql: "SELECT * FROM operation_events WHERE id = ?", arguments: [id]).map(Self.event)
    }
    private static func attempt(_ id: String, in db: GRDB.Database) throws -> OperationAttempt? {
        try Row.fetchOne(db, sql: "SELECT * FROM operation_attempts WHERE id = ?", arguments: [id]).map(Self.attempt)
    }
    static func input(_ row: Row) -> OperationInput {
        .init(id: row["id"], lineageID: row["lineage_id"], inputVersion: row["input_version"], capturedAt: row["captured_at"], text: row["text"])
    }
    static func context(_ row: Row) throws -> OperationContext {
        let configuration = try JSONDecoder().decode(OperationConfiguration.self, from: Data((row["configuration_json"] as String).utf8))
        let value = try OperationContext(capturedAt: row["captured_at"], completeness: try decode(row["completeness"]),
            appVersion: row["app_version"], appBuild: row["app_build"], ruleVersion: row["rule_version"],
            requestedModel: row["requested_model"], configuration: configuration)
        guard value.id == row["id"] as String else { throw OperationStoreError.invalid("stored_context_digest") }
        return value
    }
    static func attempt(_ row: Row) throws -> OperationAttempt {
        .init(id: row["id"], inputID: row["input_id"], contextID: row["context_id"], targetKind: try decode(row["target_kind"]),
              targetID: row["target_id"], routeSource: try decode(row["route_source"]), selectionOrigin: try decode(row["selection_origin"]),
              confirmationSource: try decode(row["confirmation_source"]), decisionEventID: row["decision_event_id"],
              firstChoiceEventID: row["first_choice_event_id"], retryOfAttemptID: row["retry_of_attempt_id"])
    }
    static func event(_ row: Row) throws -> OperationEvent {
        .init(sequence: row["sequence"], id: row["id"], inputID: row["input_id"], contextID: row["context_id"],
              runID: row["run_id"], occurredAt: row["occurred_at"], kind: try decode(row["kind"]),
              attemptID: row["attempt_id"], requestID: row["request_id"], targetKind: try optional(row["target_kind"]),
              targetID: row["target_id"], routeSource: try optional(row["route_source"]), outcome: try optional(row["outcome"]),
              reasonCode: row["reason_code"], durationMS: row["duration_ms"], detailVersion: row["detail_version"],
              details: try JSONDecoder().decode(OperationDetails.self, from: Data((row["details_json"] as String).utf8)),
              legacySource: try optional(row["legacy_source"]), legacyID: row["legacy_id"])
    }
    private static func decode<T: RawRepresentable>(_ raw: String) throws -> T where T.RawValue == String {
        guard let value = T(rawValue: raw) else { throw OperationStoreError.invalid("stored_enum") }
        return value
    }
    private static func optional<T: RawRepresentable>(_ raw: String?) throws -> T? where T.RawValue == String {
        guard let raw else { return nil }
        return try decode(raw)
    }
}
