import Foundation
import os

struct OperationToken: Sendable {
    let generation: Int64
    let runID: String
    let input: OperationInput
    let context: OperationContext

    var inputID: String { input.id }
    var contextID: String { context.id }
    var lineageID: String { input.lineageID }
}

/// Runtime callers only copy immutable facts into a bounded queue. Database and state-file
/// work never runs on the caller's actor. A token is a capability for one existing input,
/// not permission to recreate it when a delayed callback arrives.
final class OperationRecorder: @unchecked Sendable {
    enum Integrity: String, Codable, Sendable { case complete, incomplete, unknown }

    struct Status: Codable, Sendable {
        let enabled: Bool
        let retentionDays: Int
        let generation: Int64
        let runID: String
        let inputCount: Int
        let contextCount: Int
        let attemptCount: Int
        let eventCount: Int
        let storedBytes: Int64
        let pendingCount: Int
        let integrity: Integrity
        let firstKnownGapAt: Int64?
        let reasonCodes: [String]
        let countsAvailable: Bool
    }

    private enum Reason: String, Codable, CaseIterable, Sendable {
        case queueFull = "queue_full", inputTooLarge = "input_too_large"
        case databaseWriteFailed = "database_write_failed", invalidEvent = "invalid_event"
        case exitNotDrained = "exit_not_drained", captureStorageUnavailable = "capture_storage_unavailable"
        case uncleanRestart = "unclean_restart", stateFileUnreadable = "state_file_unreadable"
        case stateFileUnwritable = "state_file_unwritable", databaseReadFailed = "database_read_failed"
        case storageUnavailable = "storage_unavailable"

        var isKnownGap: Bool {
            switch self {
            case .queueFull, .inputTooLarge, .databaseWriteFailed, .invalidEvent,
                 .exitNotDrained, .captureStorageUnavailable: true
            default: false
            }
        }
    }

    /// Contains no input, event, target, preferences, or second copy of operation facts.
    private struct DurableState: Codable {
        let schemaVersion: Int
        let generation: Int64
        let runID: String
        let cleanExit: Bool
        let firstKnownGapAt: Int64?
        let reasonCodes: [Reason]
    }

    private struct Gate {
        var enabled: Bool
        var retentionDays: Int
        var generation: Int64
        let runID: String
        let storageAvailable: Bool
        var pendingCount = 0
        var pendingBytes = 0
        var pendingLineages: [String: Int] = [:]
        var closing = false
        var cleanExit = false
        var shutdownAttempt: UUID?
        var retiredLineages: Set<String> = []
        var inflight: [String: String] = [:]
        // Separate generations retain new failures when an earlier clear is still queued.
        var issues: [Int64: [Reason: Int64]] = [:]
        var persistenceScheduled = false
        var persistenceRevision: UInt64 = 0
        var retentionScheduled = false

        var reasons: Set<Reason> { Set(issues.values.flatMap(\.keys)) }
        var firstKnownGapAt: Int64? {
            issues.values.flatMap { $0.filter { $0.key.isKnownGap }.values }.min()
        }
        var integrity: Integrity {
            if reasons.contains(where: \.isKnownGap) { return .incomplete }
            return reasons.isEmpty ? .complete : .unknown
        }
    }

    private struct ExportScope: Sendable {
        let enabled: Bool
        let retentionDays: Int
        let generation: Int64
        let runID: String
    }

    enum Failure: Error, LocalizedError, Sendable {
        case invalidRetention, destinationExists, invalidDestination
        var errorDescription: String? {
            switch self {
            case .invalidRetention: "Retention must be between 1 and 3,650 days."
            case .destinationExists: "The export folder already exists. Choose a new folder."
            case .invalidDestination: "The export folder is not a local file location."
            }
        }
    }

    private let store: OperationStore
    private let queue = DispatchQueue(label: "Jotway.operations", qos: .utility)
    private let stateQueue = DispatchQueue(label: "Jotway.operations.integrity", qos: .utility)
    private let gate: OSAllocatedUnfairLock<Gate>
    private let stateFileURL: URL?
    private let queueLimit: Int
    private let maximumPendingBytes: Int

    init(repository: LauncherStore, stateFileURL: URL? = nil, enabled: Bool = true,
         retentionDays: Int = 90, queueLimit: Int = 256,
         maximumPendingBytes: Int = 16 * 1_024 * 1_024, storageAvailable: Bool = true) {
        store = OperationStore(repository: repository)
        self.stateFileURL = stateFileURL
        self.queueLimit = max(1, queueLimit)
        self.maximumPendingBytes = max(1, maximumPendingBytes)
        let generation = Self.nowMilliseconds()
        var initial = Gate(enabled: enabled, retentionDays: min(3_650, max(1, retentionDays)),
                           generation: generation, runID: UUID().uuidString, storageAvailable: storageAvailable)
        if !storageAvailable { initial.issues[generation] = [.storageUnavailable: Self.nowMilliseconds()] }
        gate = OSAllocatedUnfairLock(initialState: initial)
        // First state-file task always precedes the database queue's opening barrier.
        stateQueue.async { self.initializeDurableState() }
        queue.async {
            self.stateQueue.sync {}
            // Disabling is persisted by the caller before its asynchronous deletion.
            // Resume that deletion if a previous process ended before it completed.
            if !enabled {
                do { try self.store.removeAll() }
                catch { self.markIssue(.databaseWriteFailed, generation: generation) }
            }
        }
        requestRetention()
    }

    static func nowMilliseconds() -> Int64 { Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down)) }
    func newLineageID() -> String { UUID().uuidString }
    var currentGeneration: Int64 { gate.withLock { $0.generation } }
    var isEnabled: Bool { gate.withLock { $0.enabled } }

    func isCurrent(_ token: OperationToken) -> Bool {
        gate.withLock { Self.accepts(token, in: $0) }
    }

    func isRetired(lineageID: String) -> Bool {
        gate.withLock { $0.retiredLineages.contains(lineageID) }
    }

    func capture(input: OperationInput, context: OperationContext,
                 trigger: OperationCaptureTrigger) -> OperationToken? {
        let token = gate.withLock { value -> OperationToken? in
            guard value.enabled, !value.closing, !value.retiredLineages.contains(input.lineageID) else { return nil }
            return OperationToken(generation: value.generation, runID: value.runID, input: input, context: context)
        }
        guard let token else { return nil }
        let event = OperationEvent(id: UUID().uuidString, inputID: input.id, contextID: context.id,
            runID: token.runID, occurredAt: Self.nowMilliseconds(), kind: .inputCaptured,
            details: .capture(.init(trigger: trigger)))
        let contextBytes = (try? operationJSON(context).count) ?? maximumPendingBytes
        guard enqueue(token, bytes: input.utf8Bytes + contextBytes + 512, work: {
            try self.store.capture(input: input, context: context, event: event)
        }) else { return nil }
        return token
    }

    @discardableResult
    func record(_ event: OperationEvent, token: OperationToken) -> Bool {
        guard matches(event, token: token) else {
            if isCurrent(token) { markIssue(.invalidEvent, generation: token.generation) }
            return false
        }
        return enqueue(token, bytes: (try? operationJSON(event).count) ?? maximumPendingBytes) {
            try self.store.append(event)
        }
    }

    @discardableResult
    func confirm(_ attempt: OperationAttempt, event: OperationEvent, token: OperationToken) -> Bool {
        guard matches(event, token: token), event.kind == .confirmRequested,
              event.attemptID == attempt.id, attempt.inputID == token.inputID,
              attempt.contextID == token.contextID else {
            if isCurrent(token) { markIssue(.invalidEvent, generation: token.generation) }
            return false
        }
        let bytes = ((try? operationJSON(event).count) ?? maximumPendingBytes)
            + ((try? operationJSON(attempt).count) ?? maximumPendingBytes)
        return enqueue(token, bytes: bytes) { try self.store.confirm(attempt: attempt, event: event) }
    }

    func markInflight(_ token: OperationToken, activityID: String, active: Bool) {
        gate.withLock { value in
            let key = "\(token.runID):\(token.generation):\(activityID)"
            if active {
                guard Self.accepts(token, in: value) else { return }
                value.inflight[key] = token.lineageID
            } else {
                value.inflight.removeValue(forKey: key)
            }
        }
        if !active { requestRetention() }
    }

    private static func accepts(_ token: OperationToken, in value: Gate) -> Bool {
        value.enabled && !value.closing && token.generation == value.generation
            && token.runID == value.runID && !value.retiredLineages.contains(token.lineageID)
    }

    private func matches(_ event: OperationEvent, token: OperationToken) -> Bool {
        event.inputID == token.inputID && event.contextID == token.contextID
            && event.runID == token.runID && event.kind != .legacyObservation
    }

    private func enqueue(_ token: OperationToken, bytes: Int,
                         work: @escaping @Sendable () throws -> Bool) -> Bool {
        let admission = gate.withLock { value -> (accepted: Bool, issue: Reason?) in
            guard Self.accepts(token, in: value) else { return (false, nil) }
            guard value.storageAvailable else { return (false, .captureStorageUnavailable) }
            guard bytes <= maximumPendingBytes else { return (false, .inputTooLarge) }
            guard value.pendingCount < queueLimit, bytes <= maximumPendingBytes - value.pendingBytes else {
                return (false, .queueFull)
            }
            value.pendingCount += 1
            value.pendingBytes += bytes
            value.pendingLineages[token.lineageID, default: 0] += 1
            // Admission and dispatch share the same lock as generation-changing controls.
            queue.async {
                defer {
                    self.gate.withLock { value in
                        value.pendingCount -= 1
                        value.pendingBytes -= bytes
                        let count = (value.pendingLineages[token.lineageID] ?? 1) - 1
                        value.pendingLineages[token.lineageID] = count > 0 ? count : nil
                    }
                }
                guard self.gate.withLock({ value in
                    value.enabled && token.generation == value.generation && token.runID == value.runID
                        && !value.retiredLineages.contains(token.lineageID)
                }) else { return }
                do { _ = try work(); self.requestRetention() }
                catch { self.markIssue(.databaseWriteFailed, generation: token.generation) }
            }
            return (true, nil)
        }
        if let issue = admission.issue { markIssue(issue, generation: token.generation) }
        return admission.accepted
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { self.stateQueue.sync {}; continuation.resume() }
        }
    }

    func status() async -> Status {
        await withCheckedContinuation { continuation in
            queue.async {
                self.stateQueue.sync {}
                do { continuation.resume(returning: self.makeStatus(statistics: try self.store.statistics())) }
                catch {
                    self.markIssue(.databaseReadFailed)
                    continuation.resume(returning: self.makeStatus(statistics: nil))
                }
            }
        }
    }

    func clear() async throws {
        try await replaceCollection(enabled: nil, resetsIntegrity: true)
    }

    func setEnabled(_ enabled: Bool) async throws {
        if enabled {
            await withCheckedContinuation { continuation in
                gate.withLock { value in
                    value.enabled = true
                    value.closing = false
                    value.cleanExit = false
                    value.persistenceRevision &+= 1
                    queue.async { self.persistSynchronously(); continuation.resume() }
                }
            }
        } else {
            try await replaceCollection(enabled: false, resetsIntegrity: false)
        }
    }

    private func replaceCollection(enabled: Bool?, resetsIntegrity: Bool) async throws {
        try await withCheckedThrowingContinuation { continuation in
            gate.withLock { value in
                value.generation &+= 1
                if let enabled { value.enabled = enabled }
                value.cleanExit = false
                value.inflight.removeAll()
                value.retiredLineages.removeAll()
                value.persistenceRevision &+= 1
                let generation = value.generation
                queue.async {
                    do {
                        try self.store.removeAll()
                        if resetsIntegrity {
                            self.gate.withLock { value in
                                value.issues = value.issues.filter { $0.key >= generation }
                                if !value.storageAvailable {
                                    value.issues[value.generation, default: [:]][.storageUnavailable] = Self.nowMilliseconds()
                                }
                                value.persistenceRevision &+= 1
                            }
                        }
                        self.persistSynchronously()
                        continuation.resume()
                    } catch {
                        self.markIssue(.databaseWriteFailed, generation: generation)
                        self.persistSynchronously()
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    func setRetention(days: Int) async throws {
        guard (1...3_650).contains(days) else { throw Failure.invalidRetention }
        try await withCheckedThrowingContinuation { continuation in
            gate.withLock { value in
                value.retentionDays = days
                queue.async {
                    do { try self.performRetention(); continuation.resume() }
                    catch { self.markIssue(.databaseWriteFailed); continuation.resume(throwing: error) }
                }
            }
        }
    }

    private func requestRetention() {
        gate.withLock { value in
            guard !value.retentionScheduled else { return }
            value.retentionScheduled = true
            queue.async {
                defer { self.gate.withLock { $0.retentionScheduled = false } }
                do { try self.performRetention() }
                catch { self.markIssue(.databaseWriteFailed) }
            }
        }
    }

    private func performRetention() throws {
        let scope = gate.withLock { (days: $0.retentionDays, generation: $0.generation) }
        let cutoff = Self.nowMilliseconds() - Int64(scope.days) * 86_400_000
        let candidates = try store.expiredLineages(before: cutoff)
        let retired = gate.withLock { value -> Set<String> in
            guard value.generation == scope.generation else { return [] }
            let protected = Set(value.inflight.values).union(value.pendingLineages.keys)
            let retired = candidates.subtracting(protected)
            // Linearize expiration with capture/in-flight admission before disk work.
            value.retiredLineages.formUnion(retired)
            return retired
        }
        if !retired.isEmpty { _ = try store.expire(lineages: retired) }
    }

    func export(to directory: URL) async throws -> URL {
        let snapshot: (OperationSnapshot, Status) = try await withCheckedThrowingContinuation { continuation in
            gate.withLock { value in
                // Freeze the control epoch at the same FIFO boundary as the read. A later
                // clear can invalidate runtime tokens immediately without relabeling this export.
                let scope = ExportScope(enabled: value.enabled, retentionDays: value.retentionDays,
                                        generation: value.generation, runID: value.runID)
                queue.async {
                    self.stateQueue.sync {}
                    do {
                        let snapshot = try self.store.exportSnapshot()
                        continuation.resume(returning: (snapshot.records,
                            self.makeStatus(statistics: snapshot.statistics, scope: scope)))
                    } catch {
                        self.markIssue(.databaseReadFailed)
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
        return try await Task.detached(priority: .utility) {
            try OperationExport.write(snapshot.0, status: snapshot.1, to: directory)
        }.value
    }

    @discardableResult
    func flushBeforeExit(timeout: TimeInterval = 1) -> Bool {
        let completed = DispatchSemaphore(value: 0)
        let attempt = UUID()
        gate.withLock { value in
            value.closing = true
            value.shutdownAttempt = attempt
            queue.async {
                self.gate.withLock { value in
                    if value.shutdownAttempt == attempt { value.cleanExit = true; value.persistenceRevision &+= 1 }
                }
                self.persistSynchronously()
                completed.signal()
            }
        }
        guard completed.wait(timeout: .now() + max(0, timeout)) == .success else {
            gate.withLock { value in value.shutdownAttempt = nil; value.cleanExit = false }
            markIssue(.exitNotDrained)
            // This is the explicit termination boundary, never a runtime input path.
            persistSynchronously()
            return false
        }
        return true
    }

    private func makeStatus(statistics: OperationStore.Statistics?, scope: ExportScope? = nil) -> Status {
        gate.withLock { value in
            Status(enabled: scope?.enabled ?? value.enabled, retentionDays: scope?.retentionDays ?? value.retentionDays,
                generation: scope?.generation ?? value.generation, runID: scope?.runID ?? value.runID,
                inputCount: statistics?.inputCount ?? 0, contextCount: statistics?.contextCount ?? 0,
                attemptCount: statistics?.attemptCount ?? 0, eventCount: statistics?.eventCount ?? 0,
                storedBytes: statistics?.storedBytes ?? 0, pendingCount: value.pendingCount, integrity: value.integrity,
                firstKnownGapAt: value.firstKnownGapAt, reasonCodes: value.reasons.map(\.rawValue).sorted(),
                countsAvailable: statistics != nil)
        }
    }

    private func markIssue(_ reason: Reason, generation: Int64? = nil, schedulePersistence: Bool = true) {
        gate.withLock { value in
            if let generation, generation != value.generation { return }
            let generation = generation ?? value.generation
            if value.issues[generation]?[reason] == nil {
                value.issues[generation, default: [:]][reason] = Self.nowMilliseconds()
                value.persistenceRevision &+= 1
            }
        }
        if schedulePersistence { requestPersistence() }
    }

    private func requestPersistence() {
        guard stateFileURL != nil else { return }
        gate.withLock { value in
            guard !value.persistenceScheduled else { return }
            value.persistenceScheduled = true
            stateQueue.async {
                let revision = self.gate.withLock { $0.persistenceRevision }
                self.persistDurableState()
                let changed = self.gate.withLock { value in
                    value.persistenceScheduled = false
                    return value.persistenceRevision != revision
                }
                if changed { self.requestPersistence() }
            }
        }
    }

    private func persistSynchronously() { stateQueue.sync { self.persistDurableState() } }

    private func initializeDurableState() {
        guard let stateFileURL else { return }
        guard stateFileURL.isFileURL else { markIssue(.stateFileUnreadable, schedulePersistence: false); return }
        do {
            if FileManager.default.fileExists(atPath: stateFileURL.path) {
                let size = try stateFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 8_192 else { throw CocoaError(.fileReadCorruptFile) }
                let previous = try JSONDecoder().decode(DurableState.self, from: Data(contentsOf: stateFileURL))
                guard previous.schemaVersion == 1, !previous.runID.isEmpty,
                      previous.reasonCodes.count <= Reason.allCases.count,
                      previous.reasonCodes.contains(where: \.isKnownGap) == (previous.firstKnownGapAt != nil)
                else { throw CocoaError(.fileReadCorruptFile) }
                gate.withLock { value in
                    for reason in previous.reasonCodes {
                        value.issues[Int64.min, default: [:]][reason] = previous.firstKnownGapAt ?? Self.nowMilliseconds()
                    }
                    if !previous.cleanExit {
                        value.issues[Int64.min, default: [:]][.uncleanRestart] = Self.nowMilliseconds()
                    }
                    value.persistenceRevision &+= 1
                }
            }
        } catch { markIssue(.stateFileUnreadable, schedulePersistence: false) }
        persistDurableState()
    }

    private func persistDurableState() {
        guard let stateFileURL else { return }
        guard stateFileURL.isFileURL else { markIssue(.stateFileUnwritable, schedulePersistence: false); return }
        let state = gate.withLock { value in
            DurableState(schemaVersion: 1, generation: value.generation, runID: value.runID,
                         cleanExit: value.cleanExit, firstKnownGapAt: value.firstKnownGapAt,
                         reasonCodes: value.reasons.sorted { $0.rawValue < $1.rawValue })
        }
        do {
            let data = try operationJSON(state)
            guard data.count <= 8_192 else { throw CocoaError(.fileWriteUnknown) }
            try FileManager.default.createDirectory(at: stateFileURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try data.write(to: stateFileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateFileURL.path)
        } catch { markIssue(.stateFileUnwritable, schedulePersistence: false) }
    }
}
