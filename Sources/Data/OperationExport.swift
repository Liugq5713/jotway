import Foundation

/// All four files derive from the exact same immutable read snapshot. Export rendering and
/// file I/O happen after releasing the recorder queue, so a large export cannot stall capture.
enum OperationExport {
    private struct Row<Value: Encodable>: Encodable {
        let schemaVersion = 1
        let recordType: String
        let data: Value
    }

    private struct Metadata: Encodable {
        let exportedAt: Int64
        let status: OperationRecorder.Status
        let scope = "Jotway input versions, routing context, explicit choices, confirmations, and observed outcomes. Includes unsubmitted text; excludes keystrokes, other apps, clipboard monitoring, secrets, and full service responses."
        let ordering = "Event sequence is authoritative. Unix millisecond timestamps are not ordering guarantees. Generation and runID isolate collection; generation is not a chronology."
        let completeness = "A missing terminal event means unknown. Successful outcomes do not prove intermediate events were captured. Legacy observations remain partial and are not attempts."
        let csvTextSafety = "CSV cells beginning with formula/control characters are prefixed with an apostrophe. JSONL preserves original values."
    }

    static func write(_ snapshot: OperationSnapshot, status: OperationRecorder.Status, to directory: URL) throws -> URL {
        guard directory.isFileURL else { throw OperationRecorder.Failure.invalidDestination }
        let files = FileManager.default
        guard !files.fileExists(atPath: directory.path) else { throw OperationRecorder.Failure.destinationExists }
        let parent = directory.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".jotway-export-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: temporary, withIntermediateDirectories: false,
                                  attributes: [.posixPermissions: 0o700])
        do {
            try writeJSONL(snapshot, status: status, to: temporary.appendingPathComponent("records.jsonl"))
            try writeCSV(attemptRows(snapshot), to: temporary.appendingPathComponent("attempts.csv"))
            try writeCSV(unsubmittedRows(snapshot), to: temporary.appendingPathComponent("unsubmitted.csv"))
            try writeCSV(legacyRows(snapshot), to: temporary.appendingPathComponent("legacy.csv"))
            // Rename only after every file has been completed; never overwrite another export.
            try files.moveItem(at: temporary, to: directory)
            return directory
        } catch {
            try? files.removeItem(at: temporary)
            throw error
        }
    }

    private static func writeJSONL(_ snapshot: OperationSnapshot, status: OperationRecorder.Status, to url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        func append<Value: Encodable>(_ type: String, _ value: Value) throws {
            var data = try operationJSON(Row(recordType: type, data: value))
            data.append(0x0a)
            try file.write(contentsOf: data)
        }
        try append("metadata", Metadata(exportedAt: OperationRecorder.nowMilliseconds(), status: status))
        for value in snapshot.inputs.sorted(by: { $0.id < $1.id }) { try append("input", value) }
        for value in snapshot.contexts.sorted(by: { $0.id < $1.id }) { try append("context", value) }
        for value in snapshot.attempts.sorted(by: { $0.id < $1.id }) { try append("attempt", value) }
        for value in snapshot.events.sorted(by: { ($0.sequence ?? 0) < ($1.sequence ?? 0) }) { try append("event", value) }
        try file.synchronize()
    }

    private static func attemptRows(_ snapshot: OperationSnapshot) -> [[String]] {
        let inputs = Dictionary(uniqueKeysWithValues: snapshot.inputs.map { ($0.id, $0) })
        let contexts = Dictionary(uniqueKeysWithValues: snapshot.contexts.map { ($0.id, $0) })
        let events = Dictionary(uniqueKeysWithValues: snapshot.events.map { ($0.id, $0) })
        let attemptEvents = Dictionary(grouping: snapshot.events.filter { $0.attemptID != nil }, by: { $0.attemptID! })
        let inputEvents = Dictionary(grouping: snapshot.events, by: \.inputID)
        var rows = [["attempt_id", "lineage_id", "input_version", "input_id", "text", "utf8_bytes",
            "confirmed_at_ms", "confirm_sequence", "previous_presented_target_kind", "previous_presented_target_id",
            "previous_presented_route_source", "decision_event_id", "first_choice_event_id",
            "final_target_kind", "final_target_id", "route_source", "selection_origin", "confirmation_source",
            "submission", "submission_reason", "execution_outcome", "execution_reason", "execution_duration_ms",
            "retry_of_attempt_id", "context_id", "rule_version", "requested_model", "actual_model",
            "text_transform", "expected_target", "problem_category", "candidate_rule", "notes"]]
        let ordered = snapshot.attempts.sorted {
            let lhs = attemptEvents[$0.id]?.first { $0.kind == .confirmRequested }?.sequence ?? 0
            let rhs = attemptEvents[$1.id]?.first { $0.kind == .confirmRequested }?.sequence ?? 0
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
        for attempt in ordered {
            guard let input = inputs[attempt.inputID], let context = contexts[attempt.contextID] else { continue }
            let related = attemptEvents[attempt.id] ?? []
            let confirmation = related.first { $0.kind == .confirmRequested }
            let submission = related.first { $0.kind == .submissionAccepted || $0.kind == .submissionRejected }
            let execution = related.first { $0.kind == .executionFinished }
            let firstChoice = attempt.firstChoiceEventID.flatMap { events[$0] }
            let previous: OperationEvent? = {
                guard case .selection(let selection) = firstChoice?.details,
                      let id = selection.previousPresentedEventID else { return nil }
                return events[id]
            }()
            let modelEvent = (inputEvents[attempt.inputID] ?? []).last {
                $0.kind == .recognitionFinished && $0.contextID == attempt.contextID
                    && ($0.sequence ?? 0) < (confirmation?.sequence ?? .max)
            }
            let actualModel: String? = {
                guard case .recognition(let value) = modelEvent?.details else { return nil }
                return value.actualModel
            }()
            let transform: String = {
                guard case .confirmation(let value) = confirmation?.details else { return "unknown" }
                return value.textTransform.rawValue
            }()
            rows.append([attempt.id, input.lineageID, String(input.inputVersion), input.id, input.text,
                String(input.utf8Bytes), number(confirmation?.occurredAt), number(confirmation?.sequence),
                previous?.targetKind?.rawValue ?? "", previous?.targetID ?? "", previous?.routeSource?.rawValue ?? "",
                attempt.decisionEventID ?? "", attempt.firstChoiceEventID ?? "", attempt.targetKind.rawValue,
                attempt.targetID, attempt.routeSource.rawValue, attempt.selectionOrigin.rawValue,
                attempt.confirmationSource.rawValue,
                submission.map { $0.kind == .submissionAccepted ? "accepted" : "rejected" } ?? "unknown",
                submission?.reasonCode ?? "", execution?.outcome?.rawValue ?? "unknown", execution?.reasonCode ?? "",
                number(execution?.durationMS), attempt.retryOfAttemptID ?? "", context.id, context.ruleVersion ?? "",
                context.requestedModel ?? "", actualModel ?? "", transform, "", "", "", ""])
        }
        return rows
    }

    private static func unsubmittedRows(_ snapshot: OperationSnapshot) -> [[String]] {
        let attempted = Set(snapshot.attempts.map(\.inputID))
        let legacy = Set(snapshot.events.filter { $0.kind == .legacyObservation }.map(\.inputID))
        let events = Dictionary(grouping: snapshot.events, by: \.inputID)
        var rows = [["input_id", "lineage_id", "input_version", "captured_at_ms", "text", "utf8_bytes",
                     "last_event_sequence", "last_event_kind", "last_event_at_ms", "status",
                     "expected_target", "problem_category", "candidate_rule", "notes"]]
        for input in snapshot.inputs.sorted(by: { $0.capturedAt == $1.capturedAt ? $0.id < $1.id : $0.capturedAt < $1.capturedAt })
            where !attempted.contains(input.id) && !legacy.contains(input.id) {
            let last = events[input.id]?.max { ($0.sequence ?? 0) < ($1.sequence ?? 0) }
            rows.append([input.id, input.lineageID, String(input.inputVersion), String(input.capturedAt), input.text,
                String(input.utf8Bytes), number(last?.sequence), last?.kind.rawValue ?? "", number(last?.occurredAt),
                "no_confirmed_attempt", "", "", "", ""])
        }
        return rows
    }

    private static func legacyRows(_ snapshot: OperationSnapshot) throws -> [[String]] {
        let inputs = Dictionary(uniqueKeysWithValues: snapshot.inputs.map { ($0.id, $0) })
        var rows = [["legacy_source", "legacy_id", "event_id", "sequence", "input_id", "lineage_id", "text",
                     "observed_at_ms", "observed_at_known", "target_kind", "target_id", "completeness",
                     "sample_json", "execution_json", "data_json", "corrected_at_sql_json",
                     "expected_target", "problem_category", "candidate_rule", "notes"]]
        for event in snapshot.events where event.kind == .legacyObservation {
            guard let input = inputs[event.inputID], case .legacy(let details) = event.details else { continue }
            let original = try OperationMigration.reconstruct(event: event, input: input)
            rows.append([event.legacySource?.rawValue ?? "", event.legacyID ?? "", event.id, number(event.sequence),
                input.id, input.lineageID, input.text, details.occurredAtKnown ? String(event.occurredAt) : "",
                String(details.occurredAtKnown), event.targetKind?.rawValue ?? "", event.targetID ?? "", "legacy_partial",
                original.sample?.jsonString ?? "", original.execution?.jsonString ?? "", original.data?.jsonString ?? "",
                details.correctedAt?.jsonString ?? "", "", "", "", ""])
        }
        return rows
    }

    private static func number(_ value: Int64?) -> String { value.map(String.init) ?? "" }

    private static func writeCSV(_ rows: [[String]], to url: URL) throws {
        let contents = rows.map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        try Data(contents.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func csvCell(_ value: String) -> String {
        let ignoredPrefix = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        let initial = value.unicodeScalars.drop(while: { ignoredPrefix.contains($0) || $0.value == 0xfeff }).first
        let formula = initial.map { "=+-@".unicodeScalars.contains($0) } == true
            || value.first == "\t" || value.first == "\r" || value.first == "\n"
        let safe = formula ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
