import Foundation
import GRDB

enum OperationMigration {
    static let schema = """
        CREATE TABLE operation_inputs (
            id TEXT PRIMARY KEY NOT NULL,
            lineage_id TEXT NOT NULL,
            input_version INTEGER NOT NULL CHECK (input_version >= 0),
            captured_at INTEGER NOT NULL,
            text TEXT NOT NULL,
            utf8_bytes INTEGER NOT NULL CHECK (utf8_bytes = length(CAST(text AS BLOB))),
            UNIQUE (lineage_id, input_version)
        );

        CREATE TABLE operation_contexts (
            id TEXT PRIMARY KEY NOT NULL,
            captured_at INTEGER NOT NULL,
            schema_version INTEGER NOT NULL CHECK (schema_version = 1),
            completeness TEXT NOT NULL CHECK (completeness IN ('complete', 'legacy_partial')),
            app_version TEXT,
            app_build TEXT,
            rule_version TEXT,
            requested_model TEXT,
            configuration_json TEXT NOT NULL
                CHECK (json_valid(configuration_json) AND json_type(configuration_json) = 'object')
        );

        CREATE TABLE operation_attempts (
            id TEXT PRIMARY KEY NOT NULL,
            input_id TEXT NOT NULL REFERENCES operation_inputs(id) ON DELETE CASCADE,
            context_id TEXT NOT NULL REFERENCES operation_contexts(id),
            target_kind TEXT NOT NULL CHECK (target_kind IN ('action', 'application')),
            target_id TEXT NOT NULL,
            route_source TEXT NOT NULL CHECK (route_source IN (
                'explicit', 'user_rule', 'local_keyword', 'local_application', 'model', 'fallback'
            )),
            selection_origin TEXT NOT NULL CHECK (selection_origin IN (
                'user_choice', 'setup_completion', 'automatic'
            )),
            confirmation_source TEXT NOT NULL CHECK (confirmation_source IN (
                'enter', 'command_enter', 'button'
            )),
            decision_event_id TEXT REFERENCES operation_events(id) ON DELETE SET NULL,
            first_choice_event_id TEXT REFERENCES operation_events(id) ON DELETE SET NULL,
            retry_of_attempt_id TEXT REFERENCES operation_attempts(id) ON DELETE SET NULL,
            UNIQUE (id, input_id, context_id),
            CHECK (retry_of_attempt_id IS NULL OR retry_of_attempt_id <> id)
        );

        CREATE TABLE operation_events (
            sequence INTEGER PRIMARY KEY AUTOINCREMENT,
            id TEXT NOT NULL UNIQUE,
            input_id TEXT NOT NULL REFERENCES operation_inputs(id) ON DELETE CASCADE,
            context_id TEXT NOT NULL REFERENCES operation_contexts(id),
            run_id TEXT,
            occurred_at INTEGER NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN (
                'input_captured', 'panel_opened', 'panel_hidden',
                'recognition_started', 'recognition_finished', 'route_presented', 'target_selected',
                'setup_started', 'setup_finished', 'confirmation_blocked', 'confirm_requested',
                'submission_accepted', 'submission_rejected', 'execution_finished',
                'draft_restored', 'draft_cleared', 'legacy_observation'
            )),
            attempt_id TEXT,
            request_id TEXT,
            target_kind TEXT CHECK (target_kind IN ('action', 'application', 'setup', 'unknown')),
            target_id TEXT,
            route_source TEXT CHECK (route_source IN (
                'explicit', 'user_rule', 'local_keyword', 'local_application', 'model', 'fallback'
            )),
            outcome TEXT,
            reason_code TEXT,
            duration_ms INTEGER CHECK (duration_ms >= 0),
            detail_version INTEGER NOT NULL DEFAULT 1 CHECK (detail_version = 1),
            details_json TEXT NOT NULL DEFAULT '{}'
                CHECK (json_valid(details_json) AND json_type(details_json) = 'object'),
            legacy_source TEXT CHECK (legacy_source IN ('intent_feedback', 'intent_corrections')),
            legacy_id TEXT,
            FOREIGN KEY (attempt_id, input_id, context_id)
                REFERENCES operation_attempts(id, input_id, context_id) ON DELETE CASCADE,
            UNIQUE (legacy_source, legacy_id),
            CHECK ((target_kind IS NULL) = (target_id IS NULL)),
            CHECK (
                (kind = 'legacy_observation' AND legacy_source IS NOT NULL AND legacy_id IS NOT NULL
                    AND run_id IS NULL AND attempt_id IS NULL)
                OR (kind <> 'legacy_observation' AND legacy_source IS NULL AND legacy_id IS NULL
                    AND run_id IS NOT NULL)
            ),
            CHECK (kind NOT IN ('confirm_requested', 'submission_accepted', 'submission_rejected',
                'execution_finished') OR attempt_id IS NOT NULL),
            CHECK (kind NOT IN ('recognition_started', 'recognition_finished') OR request_id IS NOT NULL),
            CHECK (kind NOT IN ('confirm_requested', 'submission_accepted', 'submission_rejected',
                'execution_finished') OR (target_kind IS NULL AND target_id IS NULL AND route_source IS NULL))
        );

        CREATE INDEX operation_inputs_captured ON operation_inputs(captured_at);
        CREATE INDEX operation_attempts_input ON operation_attempts(input_id);
        CREATE INDEX operation_attempts_target ON operation_attempts(target_kind, target_id);
        CREATE INDEX operation_attempts_retry ON operation_attempts(retry_of_attempt_id);
        CREATE INDEX operation_events_input ON operation_events(input_id, sequence);
        CREATE INDEX operation_events_kind_time ON operation_events(kind, occurred_at);
        CREATE INDEX operation_events_attempt ON operation_events(attempt_id, sequence);
        CREATE INDEX operation_events_request ON operation_events(request_id, sequence);
        CREATE UNIQUE INDEX operation_events_confirm ON operation_events(attempt_id)
            WHERE kind = 'confirm_requested';
        CREATE UNIQUE INDEX operation_events_submission ON operation_events(attempt_id)
            WHERE kind IN ('submission_accepted', 'submission_rejected');
        CREATE UNIQUE INDEX operation_events_execution ON operation_events(attempt_id)
            WHERE kind = 'execution_finished';
        CREATE UNIQUE INDEX operation_events_recognition ON operation_events(request_id, kind)
            WHERE kind IN ('recognition_started', 'recognition_finished');
        """
}

extension OperationMigration {
    static func migrate(_ db: GRDB.Database) throws {
        // When a historical observation has no trustworthy time, retention starts when
        // it is actually captured into this store. Its original event time stays unknown.
        let migratedAt = Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
        let feedbackCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM intent_feedback") ?? 0
        let correctionCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM intent_corrections") ?? 0
        try db.execute(sql: schema)
        let context = try OperationContext(capturedAt: 0, completeness: .legacyPartial)
        if feedbackCount + correctionCount > 0 { try OperationStore.insert(context, in: db) }
        for row in try Row.fetchAll(db, sql: "SELECT * FROM intent_feedback ORDER BY id") {
            guard let id: String = row["id"], let sampleData: Data = row["sample"], let executionData: Data = row["execution"] else {
                throw OperationStoreError.invalid("legacy_feedback_row")
            }
            let sample = try OperationJSONValue.parse(sampleData)
            let execution = try OperationJSONValue.parse(executionData)
            guard case .object(var remainder) = sample, case .string(let text) = remainder.removeValue(forKey: "text") else {
                throw OperationStoreError.invalid("legacy_feedback_text")
            }
            let target = string(remainder["targetID"])
            if target != nil { remainder.removeValue(forKey: "targetID") }
            let timestamp = milliseconds(remainder["acceptedAt"])
            let identity = "legacy:intent_feedback:" + id
            let input = OperationInput(id: identity + ":input", lineageID: identity, inputVersion: 0,
                                       capturedAt: timestamp ?? migratedAt, text: text)
            let details = OperationLegacyDetails(sample: .object(remainder), execution: execution,
                movedTargetField: target == nil ? nil : "targetID", occurredAtKnown: timestamp != nil)
            let event = OperationEvent(id: identity + ":event", inputID: input.id, contextID: context.id,
                runID: nil, occurredAt: timestamp ?? 0, kind: .legacyObservation,
                targetKind: target.map { _ in targetKind(for: remainder["action"]) },
                targetID: target, details: .legacy(details), legacySource: .intentFeedback, legacyID: id)
            try OperationStore.insert(input, in: db)
            try OperationStore.append(event, in: db)
            let restored = try reconstruct(event: event, input: input)
            guard restored.sample == sample, restored.execution == execution else {
                throw OperationStoreError.invalid("legacy_feedback_reconstruction")
            }
        }
        for row in try Row.fetchAll(db, sql: "SELECT * FROM intent_corrections ORDER BY id") {
            guard let id: String = row["id"], let data: Data = row["data"] else {
                throw OperationStoreError.invalid("legacy_correction_row")
            }
            let original = try OperationJSONValue.parse(data)
            guard case .object(var remainder) = original, case .string(let text) = remainder.removeValue(forKey: "text") else {
                throw OperationStoreError.invalid("legacy_correction_text")
            }
            let target = string(remainder["chosenTargetID"])
            if target != nil { remainder.removeValue(forKey: "chosenTargetID") }
            let timestamp = milliseconds(remainder["correctedAt"])
            let identity = "legacy:intent_corrections:" + id
            let input = OperationInput(id: identity + ":input", lineageID: identity, inputVersion: 0,
                                       capturedAt: timestamp ?? migratedAt, text: text)
            let rawDate: DatabaseValue = row["correctedAt"]
            let details = OperationLegacyDetails(data: .object(remainder), movedTargetField: target == nil ? nil : "chosenTargetID",
                                                 correctedAt: try sqlValue(rawDate), occurredAtKnown: timestamp != nil)
            let event = OperationEvent(id: identity + ":event", inputID: input.id, contextID: context.id,
                runID: nil, occurredAt: timestamp ?? 0, kind: .legacyObservation,
                targetKind: target == nil ? nil : .unknown, targetID: target,
                details: .legacy(details), legacySource: .intentCorrections, legacyID: id)
            try OperationStore.insert(input, in: db)
            try OperationStore.append(event, in: db)
            guard try reconstruct(event: event, input: input).data == original else {
                throw OperationStoreError.invalid("legacy_correction_reconstruction")
            }
        }
        for (source, count) in [(OperationLegacySource.intentFeedback, feedbackCount), (.intentCorrections, correctionCount)] {
            let actual = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM operation_events WHERE legacy_source = ?", arguments: [source.rawValue])
            guard actual == count else { throw OperationStoreError.invalid("legacy_count") }
        }
        // Verify what was persisted, rather than only the transient values passed to INSERT.
        for row in try Row.fetchAll(db, sql: "SELECT * FROM operation_events ORDER BY sequence") {
            let event = try OperationStore.event(row)
            guard let inputRow = try Row.fetchOne(db, sql: "SELECT * FROM operation_inputs WHERE id = ?", arguments: [event.inputID]),
                  let source = event.legacySource, let id = event.legacyID else {
                throw OperationStoreError.invalid("legacy_reference")
            }
            let restored = try reconstruct(event: event, input: OperationStore.input(inputRow))
            if source == .intentFeedback {
                guard let old = try Row.fetchOne(db, sql: "SELECT sample,execution FROM intent_feedback WHERE id = ?", arguments: [id]),
                      restored.sample == (try OperationJSONValue.parse(old["sample"])),
                      restored.execution == (try OperationJSONValue.parse(old["execution"])) else {
                    throw OperationStoreError.invalid("stored_legacy_feedback")
                }
            } else {
                guard let old = try Row.fetchOne(db, sql: "SELECT data,correctedAt FROM intent_corrections WHERE id = ?", arguments: [id]),
                      restored.data == (try OperationJSONValue.parse(old["data"])),
                      case .legacy(let details) = event.details,
                      details.correctedAt == (try sqlValue(old["correctedAt"])) else {
                    throw OperationStoreError.invalid("stored_legacy_correction")
                }
            }
        }
        guard try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty else {
            throw OperationStoreError.invalid("legacy_foreign_keys")
        }
        try db.execute(sql: "DROP TABLE intent_feedback; DROP TABLE intent_corrections;")
    }

    struct ReconstructedLegacy: Equatable {
        var sample: OperationJSONValue?
        var execution: OperationJSONValue?
        var data: OperationJSONValue?
    }

    static func reconstruct(event: OperationEvent, input: OperationInput) throws -> ReconstructedLegacy {
        guard event.kind == .legacyObservation, input.id == event.inputID, case .legacy(let details) = event.details else {
            throw OperationStoreError.invalid("legacy_reconstruction_identity")
        }
        func restore(_ value: OperationJSONValue?) throws -> OperationJSONValue? {
            guard let value else { return nil }
            guard case .object(var object) = value, object["text"] == nil else {
                throw OperationStoreError.invalid("legacy_reconstruction_object")
            }
            object["text"] = .string(input.text)
            if let field = details.movedTargetField {
                guard object[field] == nil, let target = event.targetID else {
                    throw OperationStoreError.invalid("legacy_reconstruction_target")
                }
                object[field] = .string(target)
            }
            return .object(object)
        }
        return try .init(sample: restore(details.sample), execution: details.execution, data: restore(details.data))
    }

    private static func targetKind(for action: OperationJSONValue?) -> OperationTargetKind {
        switch string(action) {
        case "open_application": .application
        case "google", "capture", "conversation": .action
        default: .unknown
        }
    }
    private static func string(_ value: OperationJSONValue?) -> String? {
        if case .string(let string) = value, !string.isEmpty { return string }
        return nil
    }
    private static func milliseconds(_ value: OperationJSONValue?) -> Int64? {
        guard case .number(let literal) = value, let seconds = Double(literal) else { return nil }
        // Foundation's default Codable Date epoch is 2001-01-01, not Unix time.
        let milliseconds = ((seconds + 978_307_200) * 1000).rounded(.towardZero)
        guard milliseconds.isFinite, milliseconds > Double(Int64.min), milliseconds < Double(Int64.max) else { return nil }
        return Int64(milliseconds)
    }
    private static func sqlValue(_ value: DatabaseValue) throws -> OperationJSONValue {
        switch value.storage {
        case .null: return .null
        case .int64(let value): return .number(String(value))
        case .double(let value): return .number(String(value))
        case .string(let value): return .string(value)
        case .blob: throw OperationStoreError.invalid("legacy_date_blob")
        }
    }
}

extension OperationJSONValue {
    static func parse(_ data: Data) throws -> OperationJSONValue {
        var parser = LegacyJSONParser(bytes: Array(data))
        let result = try parser.value()
        parser.whitespace()
        guard parser.index == parser.bytes.count else { throw OperationStoreError.invalid("legacy_json_trailing") }
        return result
    }

    var jsonString: String {
        switch self {
        case .null: "null"
        case .bool(let value): value ? "true" : "false"
        case .string(let value): String(decoding: try! operationJSON(value), as: UTF8.self)
        case .number(let value): value
        case .array(let values): "[" + values.map(\.jsonString).joined(separator: ",") + "]"
        case .object(let values): "{" + values.keys.sorted().map {
            OperationJSONValue.string($0).jsonString + ":" + values[$0]!.jsonString
        }.joined(separator: ",") + "}"
        }
    }
}

/// A small JSON value parser retains number tokens without Double/Decimal coercion.
private struct LegacyJSONParser {
    let bytes: [UInt8]
    var index = 0
    mutating func whitespace() { while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
    mutating func consume(_ byte: UInt8) -> Bool {
        whitespace()
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }
    mutating func value(depth: Int = 0) throws -> OperationJSONValue {
        whitespace()
        guard depth < 256, index < bytes.count else { throw OperationStoreError.invalid("legacy_json") }
        switch bytes[index] {
        case 110: try literal("null"); return .null
        case 116: try literal("true"); return .bool(true)
        case 102: try literal("false"); return .bool(false)
        case 34: return .string(try string())
        case 91:
            index += 1
            var values: [OperationJSONValue] = []
            if consume(93) { return .array(values) }
            repeat { values.append(try value(depth: depth + 1)) } while consume(44)
            guard consume(93) else { throw OperationStoreError.invalid("legacy_json_array") }
            return .array(values)
        case 123:
            index += 1
            var values: [String: OperationJSONValue] = [:]
            if consume(125) { return .object(values) }
            repeat {
                whitespace()
                let key = try string()
                guard values[key] == nil, consume(58) else { throw OperationStoreError.invalid("legacy_json_key") }
                values[key] = try value(depth: depth + 1)
            } while consume(44)
            guard consume(125) else { throw OperationStoreError.invalid("legacy_json_object") }
            return .object(values)
        default:
            let start = index
            while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            let token = String(decoding: bytes[start..<index], as: UTF8.self)
            guard token.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else {
                throw OperationStoreError.invalid("legacy_json_number")
            }
            return .number(token)
        }
    }
    mutating func literal(_ value: String) throws {
        let expected = Array(value.utf8)
        guard bytes.count - index >= expected.count, Array(bytes[index..<(index + expected.count)]) == expected else {
            throw OperationStoreError.invalid("legacy_json_literal")
        }
        index += expected.count
    }
    mutating func string() throws -> String {
        guard index < bytes.count, bytes[index] == 34 else { throw OperationStoreError.invalid("legacy_json_string") }
        let start = index
        index += 1
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
            if byte == 92 { index += 1 }
        }
        throw OperationStoreError.invalid("legacy_json_string")
    }
}
