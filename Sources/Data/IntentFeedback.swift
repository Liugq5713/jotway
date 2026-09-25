import Foundation
import GRDB
import os

/// An accepted input/action pair, independent of whether the requested operation succeeds.
struct IntentFeedback: Codable, Equatable, Sendable {
    enum ConfirmationSource: String, Codable, Sendable {
        case enter
        case commandEnter = "command_enter"
    }

    struct Recognition: Codable, Equatable, Sendable {
        let source: JevDiagnostics.Source
        let requestID: UUID?
        let ruleVersion: String?
        let actualModel: String?
        var applicationMatch: JevDiagnostics.ApplicationMatch? = nil
    }

    let id: UUID
    let acceptedAt: Date
    let draftID: UUID
    let draftRevision: Int
    let text: String
    let action: JevDiagnostics.Action
    let targetID: String
    let applicationBundleID: String?
    let applicationName: String?
    let recognition: Recognition
    /// Missing on samples created before Jev §15; those historical rows were Command-Enter only.
    let confirmationSource: ConfirmationSource?
    enum Label: String, Codable, Sendable { case userAccepted = "user_accepted" }
    let label: Label

    struct Execution: Codable, Equatable, Sendable {
        enum Outcome: String, Codable, Sendable { case notStarted = "not_started", requested, accepted, opened, failed, uncertain }
        var outcome: Outcome = .notStarted
        var requestID: UUID? = nil
        var finished = false
        var observedAt = Date()
    }

    struct Entry: Sendable {
        let sample: IntentFeedback
        var execution: Execution
    }
}

extension LauncherStore {
    /// The immutable sample is inserted once. A repeated event cannot change its original text/label.
    func saveIntentFeedback(_ sample: IntentFeedback) throws -> Bool {
        let data = try JSONEncoder().encode(sample), execution = try JSONEncoder().encode(IntentFeedback.Execution())
        return try dbQueue.write { db in
            try db.execute(sql: "INSERT INTO intent_feedback(id, sample, execution) VALUES (?, ?, ?) ON CONFLICT(id) DO NOTHING",
                           arguments: [sample.id.uuidString, data, execution])
            return db.changesCount == 1
        }
    }

    func saveIntentFeedbackExecution(id: UUID, execution: IntentFeedback.Execution) throws -> Bool {
        let data = try JSONEncoder().encode(execution)
        return try dbQueue.write { db in
            guard let old = try Data.fetchOne(db, sql: "SELECT execution FROM intent_feedback WHERE id = ?", arguments: [id.uuidString]) else {
                throw DatabaseError(resultCode: .SQLITE_NOTFOUND)
            }
            let previous = try JSONDecoder().decode(IntentFeedback.Execution.self, from: old)
            guard !previous.finished else { return false }
            try db.execute(sql: "UPDATE intent_feedback SET execution = ? WHERE id = ?", arguments: [data, id.uuidString])
            return true
        }
    }

    /// Only the explicitly associated execution record is consulted.
    func intentFeedback(id: UUID) throws -> IntentFeedback.Entry? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT sample, execution FROM intent_feedback WHERE id = ?", arguments: [id.uuidString]) else { return nil }
            let sample = try JSONDecoder().decode(IntentFeedback.self, from: row["sample"])
            let execution = try JSONDecoder().decode(IntentFeedback.Execution.self, from: row["execution"])
            return IntentFeedback.Entry(sample: sample, execution: execution)
        }
    }
}

/// Short writes are serialized off the main actor, with bounded pending work and no dependency from execution.
final class IntentFeedbackStore: @unchecked Sendable {
    private let repository: LauncherStore
    private let log: RuntimeLog
    private let queue = DispatchQueue(label: "Jotway.intent-feedback", qos: .utility)
    private let pending = OSAllocatedUnfairLock(initialState: 0)

    init(repository: LauncherStore, log: RuntimeLog = .shared) {
        self.repository = repository
        self.log = log
    }

    func record(_ sample: IntentFeedback, storageAvailable: Bool = true) {
        let context = RuntimeLog.Context(log: log, module: .intent, requestID: sample.recognition.requestID ?? sample.id,
            draftID: sample.draftID, purpose: .intentFeedback, operation: .recordFeedback)
        let fields = RuntimeLog.Fields(feedbackID: sample.id, feedbackSource: sample.recognition.source,
            feedbackConfirmation: sample.confirmationSource)
        guard storageAvailable else { failure(context, fields: fields, code: .storage); return }
        enqueue(context, fields: fields) { try self.repository.saveIntentFeedback(sample) }
    }

    /// 用户把 Jev 建议改成别的目标：仅本地记一条纠正，滚动保留、永不外传。写入与执行路径解耦。
    func recordCorrection(_ correction: IntentCorrection, storageAvailable: Bool = true) {
        let context = RuntimeLog.Context(log: log, module: .intent,
            requestID: correction.recognition?.requestID ?? correction.id,
            purpose: .intentFeedback, operation: .recordFeedback)
        let fields = RuntimeLog.Fields(feedbackID: correction.id, feedbackSource: correction.recognition?.source)
        guard storageAvailable else { failure(context, fields: fields, code: .storage); return }
        enqueue(context, fields: fields) { try self.repository.saveIntentCorrection(correction) }
    }

    func execution(_ id: UUID?, _ execution: IntentFeedback.Execution) {
        guard let id else { return }
        let context = RuntimeLog.Context(log: log, module: .intent, requestID: execution.requestID ?? id,
            purpose: .intentFeedback, operation: .updateFeedback)
        let fields = RuntimeLog.Fields(feedbackID: id, feedbackExecution: execution.outcome)
        enqueue(context, fields: fields) { try self.repository.saveIntentFeedbackExecution(id: id, execution: execution) }
    }

    private func failure(_ context: RuntimeLog.Context, fields: RuntimeLog.Fields, code: RuntimeLog.Code) {
        var fields = fields
        fields.outcome = .failed; fields.errorCode = code
        context.emit(.feedbackWrite, fields)
    }

    private func enqueue(_ context: RuntimeLog.Context, fields: RuntimeLog.Fields,
                         write: @escaping @Sendable () throws -> Bool) {
        guard pending.withLock({ value in
            guard value < 64 else { return false }; value += 1; return true
        }) else { failure(context, fields: fields, code: .unavailable); return }
        queue.async {
            defer { self.pending.withLock { $0 -= 1 } }
            var fields = fields
            do {
                fields.outcome = try write() ? .success : .discarded
                context.emit(.feedbackWrite, fields)
            } catch { self.failure(context, fields: fields, code: .storage) }
        }
    }

    /// Tests can await queued writes without making the confirmation path wait for the database.
    func flush() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }

    @discardableResult func flushBeforeExit(timeout: TimeInterval = 1) -> Bool {
        let completed = DispatchSemaphore(value: 0)
        queue.async { completed.signal() }
        return completed.wait(timeout: .now() + timeout) == .success
    }
}
