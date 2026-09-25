import Foundation
import Darwin
import os

/// Content-free diagnostics. Business persistence is always independent of this best-effort writer.
final class RuntimeLog: @unchecked Sendable {
    enum Module: String, Codable, Sendable { case app, connector, ai, intent, logging }
    enum Event: String, Codable, Sendable {
        case startup, shutdown
        case requestStarted = "request_started", requestFinished = "request_finished"
        case stageStarted = "stage_started", stageFinished = "stage_finished"
        case queued = "request_queued", callStarted = "call_started", callFinished = "call_finished"
        case dropped = "logs_dropped"
        case cancellationRequested = "cancellation_requested"
        case suggestionChanged = "suggestion_changed"
        case feedbackWrite = "feedback_write"
    }
    enum Stage: String, Codable, Sendable {
        case preflight, configuration, input, intent, phase, helperLaunch = "helper_launch"
        case helperConnection = "helper_connection", helperExchange = "helper_exchange"
        case targetConnection = "target_connection", account, workspaces, projects, config, limit, encode
        case createChat, createMessage, send, lookup, service, model, format, validation
        case receipt, cleanup, metadata, persistence
    }
    enum Outcome: String, Codable, Sendable { case success, failed, uncertain, accepted, cancelled, discarded, timeout, unknown }
    enum Operation: String, Codable, Sendable { case send, verify, receiptSave = "receipt_save", metadata, generate, recognize, recordFeedback = "record_feedback", updateFeedback = "update_feedback", action }
    enum Purpose: String, Codable, Sendable { case supplement, summary, context, intentRecognition = "intent_recognition", intentFeedback = "intent_feedback", connectionTest = "connection_test", unknown }
    enum Code: String, Codable, Sendable {
        case unknown, configuration, inputTooLarge = "input_too_large", storage, stale, validation, format
        case modelMismatch = "model_mismatch", modelUnknown = "model_unknown", emptyResponse = "empty_response"
        case helperLaunch = "helper_launch", helperConnection = "helper_connection", disconnected, timeout
        case processFailed = "process_failed", unavailable, authentication, http, cancelled, rateLimited = "rate_limited"
    }
    enum Cancellation: String, Codable, Sendable { case user, unknown }
    enum Acceptance: String, Codable, Sendable {
        case systemOpen = "system_url_accepted"
    }
    enum Phase: String, Codable, Sendable {
        case ready, sending, uncertain, failed, prepared, creatingChat, chatCreated
        case creatingMessage, messageCreated, sendingMessage, opening, accepted
    }
    struct Fields: Codable, Sendable {
        var stage: Stage? = nil
        var outcome: Outcome? = nil
        var errorCode: Code? = nil
        var cancellationReason: Cancellation? = nil
        var phase: Phase? = nil
        var acceptanceMode: Acceptance? = nil
        var requestedModel: String? = nil
        var actualModel: String? = nil
        var durationMs: Int? = nil
        var queueDurationMs: Int? = nil
        var totalDurationMs: Int? = nil
        var bytes: Int? = nil
        var httpStatus: Int? = nil
        /// 启动器默认 action（如 Apple Notes）失败时的系统 OSStatus，纯数字诊断码、不含用户内容。
        var osStatus: Int? = nil
        /// 执行的 action 稳定 id（如 "apple-notes"），非用户内容。
        var actionID: String? = nil
        var exitCode: Int32? = nil
        var droppedCount: Int? = nil
        var intent: JevDiagnostics? = nil
        var feedbackID: UUID? = nil
        var feedbackSource: JevDiagnostics.Source? = nil
        var feedbackConfirmation: IntentFeedback.ConfirmationSource? = nil
        var feedbackExecution: IntentFeedback.Execution.Outcome? = nil
    }

    struct Context: Sendable {
        var log: RuntimeLog = .shared
        var module: Module = .ai
        var requestID = UUID()
        var callID: UUID? = nil
        var draftID: UUID? = nil
        var connector: String? = nil
        var provider: String? = nil
        var purpose: Purpose = .unknown
        var operation: Operation = .generate
        var started = RuntimeLog.ticks()
        let cancellation = OSAllocatedUnfairLock(initialState: Cancellation.unknown)

        func emit(_ event: Event, _ fields: Fields = .init(), at date: Date? = nil) {
            var fields = fields
            if event == .requestFinished, fields.totalDurationMs == nil { fields.totalDurationMs = RuntimeLog.milliseconds(since: started) }
            log.record(event, context: self, fields: fields, at: date)
        }
        func failed(_ stage: Stage, _ error: Error, code: Code? = nil) {
            let code = code ?? RuntimeLog.code(error)
            emit(.stageFinished, .init(stage: stage, outcome: code == .cancelled ? .cancelled : code == .stale ? .discarded : code == .timeout ? .timeout : .failed,
                errorCode: code, cancellationReason: code == .cancelled ? cancellation.withLock { $0 } : nil))
        }
    }
    @TaskLocal static var current: Context?

    static let shared = RuntimeLog(enabled: !CommandLine.arguments.contains(where: { $0.contains(".xctest") })
        && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil)
    static func ticks() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    static func milliseconds(since start: UInt64) -> Int { Int((ticks() &- start) / 1_000_000) }
    static func code(_ error: Error) -> Code {
        if error is CancellationError { return .cancelled }
        if let error = error as? any RuntimeLogError { return error.runtimeLogCode }
        if let error = error as? URLError { return error.code == .timedOut ? .timeout : error.code == .cancelled ? .cancelled : .disconnected }
        if error is DecodingError { return .format }
        return .unknown
    }

    struct Limits: Sendable {
        var fileBytes = 10_000_000
        var totalBytes = 50_000_000
        var pendingEvents = 256
    }
    struct Status: Sendable {
        var bytes = 0
        var files = 0
        var dropped = 0
        var incomplete = false
        var unavailable = false
    }
    enum Failure: Error { case unavailable, empty, incomplete }
    private struct Buffer { var pending = 0; var dropped = 0; var reported = 0; var unavailable = false; var incomplete = false }
    private struct Row: Encodable {
        let schemaVersion = 1
        let time: String
        let sessionId: UUID
        let appVersion: String
        let build: String
        let level: String
        let module: Module
        let event: Event
        let requestId: UUID
        let callId: UUID?
        let draftId: UUID?
        let connectorId: String?
        let provider: String?
        let purpose: Purpose
        let operation: Operation
        let fields: Fields

        // Keep a flat JSONL schema without accepting arbitrary dictionaries or error descriptions.
        func encode(to encoder: Encoder) throws {
            try fields.encode(to: encoder)
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(schemaVersion, forKey: .schemaVersion); try c.encode(time, forKey: .time)
            try c.encode(sessionId, forKey: .sessionId); try c.encode(appVersion, forKey: .appVersion)
            try c.encode(build, forKey: .build); try c.encode(level, forKey: .level)
            try c.encode(module, forKey: .module); try c.encode(event, forKey: .event)
            try c.encode(requestId, forKey: .requestId); try c.encodeIfPresent(callId, forKey: .callId)
            try c.encodeIfPresent(draftId, forKey: .draftId)
            try c.encodeIfPresent(connectorId, forKey: .connectorId); try c.encodeIfPresent(provider, forKey: .provider)
            try c.encode(purpose, forKey: .purpose); try c.encode(operation, forKey: .operation)
        }
        enum Keys: String, CodingKey { case schemaVersion, time, sessionId, appVersion, build, level, module, event, requestId, callId, draftId, connectorId, provider, purpose, operation }
    }

    let directory: URL
    private let enabled: Bool
    private let limits: Limits
    private let clock: @Sendable () -> Date
    private let calendar: Calendar
    private let sessionID = UUID()
    private let version: String
    private let build: String
    private let queue = DispatchQueue(label: "com.liuguangqi.jotway.runtime-log", qos: .utility)
    private let buffer = OSAllocatedUnfairLock(initialState: Buffer())
    private var repaired: Set<URL> = [] // Only accessed on queue.

    init(directory: URL? = nil, enabled: Bool = true, limits: Limits = .init(),
         calendar: Calendar = .autoupdatingCurrent, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Jotway", isDirectory: true)
        self.enabled = enabled
        self.limits = limits
        self.calendar = calendar
        self.clock = clock
        version = String((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development").prefix(32))
        build = String((Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0").prefix(32))
        if enabled {
            queue.async { [self] in
                do { try prepare(); try cleanup() }
                catch { buffer.withLock { $0.unavailable = true; $0.incomplete = true } }
            }
        }
    }

    func record(_ event: Event, context: Context, fields: Fields = .init(), at date: Date? = nil) {
        guard enabled else { return }
        // Bound strings before retaining a queued event, including untrusted response model IDs.
        var boundedFields = fields
        let models = ["deepseek/deepseek-flash", "moonshot/kimi-k2-0905-preview"]
        boundedFields.requestedModel = fields.requestedModel.map { models.contains($0) || JevDiagnostics.validModel($0, requested: true) ? $0 : "unknown" }
        boundedFields.actualModel = fields.actualModel.map { models.contains($0) || JevDiagnostics.validModel($0) ? $0 : "unknown" }
        boundedFields.intent = fields.intent?.bounded
        var boundedContext = context
        boundedContext.connector = context.connector.map { ["chrome"].contains($0) ? $0 : "unknown" }
        boundedContext.provider = context.provider.map { ["deepSeek", "jev", "moonshot"].contains($0) ? $0 : "unknown" }
        let entryFields = boundedFields, entryContext = boundedContext
        let accepted = buffer.withLock { state in
            guard state.pending < max(1, limits.pendingEvents) else {
                state.dropped += 1; state.incomplete = true; return false
            }
            state.pending += 1; return true
        }
        guard accepted else { return }
        let date = date ?? clock()
        queue.async { [self] in
            defer { buffer.withLock { $0.pending -= 1 } }
            do {
                try prepare()
                let losses = buffer.withLock { $0.dropped - $0.reported }
                if losses > 0 {
                    try append(.dropped, context: .init(log: self, module: .logging), fields: .init(droppedCount: losses), date: date)
                    buffer.withLock { $0.reported += losses }
                }
                try append(event, context: entryContext, fields: entryFields, date: date)
                buffer.withLock { $0.unavailable = false }
            } catch {
                buffer.withLock { $0.dropped += 1; $0.unavailable = true; $0.incomplete = true }
            }
        }
    }

    private func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    private func day(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    private struct File { let url: URL; let day: String; let volume: Int; let size: Int }
    private func files() throws -> [File] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            .compactMap { url in
                let name = url.lastPathComponent
                guard name.range(of: #"^jotway-\d{4}-\d{2}-\d{2}(\.\d{3,})?\.jsonl$"#, options: .regularExpression) != nil else { return nil }
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
                let parts = name.split(separator: ".")
                return File(url: url, day: String(parts[0].dropFirst("jotway-".count)), volume: parts.count == 3 ? Int(parts[1]) ?? 0 : 0, size: values.fileSize ?? 0)
            }.sorted { $0.day == $1.day ? $0.volume < $1.volume : $0.day < $1.day }
    }

    private func append(_ event: Event, context: Context, fields: Fields, date: Date) throws {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let row = Row(time: formatter.string(from: date), sessionId: sessionID, appVersion: version, build: build,
            level: [.failed, .timeout].contains(fields.outcome) ? "error" : "info", module: context.module, event: event,
            requestId: context.requestID, callId: context.callID, draftId: context.draftID,
            connectorId: context.connector.map { ["chrome"].contains($0) ? $0 : "unknown" },
            provider: context.provider.map { ["deepSeek", "jev", "moonshot"].contains($0) ? $0 : "unknown" },
            purpose: context.purpose, operation: context.operation, fields: fields)
        var bytes = try JSONEncoder().encode(row)
        bytes.append(10)
        guard bytes.count <= min(8_192, limits.fileBytes) else { throw Failure.incomplete }
        let dateKey = day(date)
        guard dateKey >= day(calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: clock()))!) else { return }
        try cleanup(reserving: bytes.count) // Do not grow an over-capacity store if deletion is failing.
        let last = try files().last { $0.day == dateKey }
        var volume = last?.volume ?? 0
        var target = last?.url ?? directory.appendingPathComponent("jotway-\(dateKey).jsonl")
        if let last {
            try repair(last.url)
            let size = try last.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            if size + bytes.count > limits.fileBytes {
                volume += 1
                target = directory.appendingPathComponent(String(format: "jotway-%@.%03d.jsonl", dateKey, volume))
            }
        }
        let descriptor = Darwin.open(target.path, O_WRONLY | O_APPEND | O_NOFOLLOW | O_CREAT, 0o600)
        guard descriptor >= 0 else { throw Failure.unavailable }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.seekToEnd()
        do { try handle.write(contentsOf: bytes) }
        catch { repaired.remove(target); throw error }
    }

    /// A killed writer may leave an incomplete last line. Earlier complete lines remain byte-for-byte intact.
    private func repair(_ url: URL) throws {
        guard !repaired.contains(url) else { return }
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        if end > 0 {
            var position = end
            var newline: UInt64 = 0
            while position > 0 {
                let count = min(position, 8_192)
                position -= count
                try handle.seek(toOffset: position)
                let data = try handle.read(upToCount: Int(count)) ?? Data()
                if let index = data.lastIndex(of: 10) { newline = position + UInt64(index) + 1; break }
            }
            if newline != end {
                try handle.truncate(atOffset: newline)
                buffer.withLock { $0.dropped += 1; $0.incomplete = true }
            }
        }
        repaired.insert(url)
    }

    private func cleanup(reserving: Int = 0) throws {
        guard reserving <= limits.totalBytes else { throw Failure.incomplete }
        let earliest = day(calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: clock()))!)
        let all = try files()
        var bytes = all.reduce(0) { $0 + $1.size }
        for file in all where file.day < earliest || bytes + reserving > limits.totalBytes {
            try FileManager.default.removeItem(at: file.url)
            bytes -= file.size
            repaired.remove(file.url)
        }
    }

    func status() async -> Status {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                var result = Status()
                if enabled {
                    do { try prepare(); try cleanup(); let all = try files(); result.files = all.count; result.bytes = all.reduce(0) { $0 + $1.size } }
                    catch { result.unavailable = true }
                }
                let state = buffer.withLock { $0 }
                result.dropped = state.dropped
                result.incomplete = state.incomplete
                result.unavailable = result.unavailable || state.unavailable
                continuation.resume(returning: result)
            }
        }
    }

    func clear() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try prepare()
                    for file in try files() { try FileManager.default.removeItem(at: file.url) }
                    repaired.removeAll()
                    buffer.withLock { $0.dropped = 0; $0.reported = 0; $0.incomplete = false; $0.unavailable = false }
                    continuation.resume()
                } catch { continuation.resume(throwing: Failure.unavailable) }
            }
        }
    }

    /// Copy on the writer queue, then compress off that queue; never wait for an external request to finish.
    func export(to destination: URL) async throws -> Bool {
        let copy: (URL, Bool) = try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("Jotway-Logs-\(UUID())", isDirectory: true)
                do {
                    try prepare(); try cleanup()
                    let all = try files()
                    guard !all.isEmpty else { throw Failure.empty }
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    for file in all {
                        try repair(file.url)
                        try FileManager.default.copyItem(at: file.url, to: root.appendingPathComponent(file.url.lastPathComponent))
                    }
                    try Jev.ruleDefinitionData().write(to: root.appendingPathComponent("\(Jev.ruleVersion).jsonl"))
                    continuation.resume(returning: (root, buffer.withLock { $0.incomplete }))
                } catch {
                    try? FileManager.default.removeItem(at: root)
                    continuation.resume(throwing: error)
                }
            }
        }
        defer { try? FileManager.default.removeItem(at: copy.0) }
        try Task.checkCancellation()
        let task = Task.detached(priority: .utility) { try ZIPExport.write(directory: copy.0, to: destination) }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        return copy.1
    }

    /// App termination gets a bounded best effort. Logging must never prevent quitting.
    @discardableResult func flush(timeout: TimeInterval = 0.25) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        queue.async { semaphore.signal() }
        return semaphore.wait(timeout: .now() + timeout) == .success
    }
}

protocol RuntimeLogError: Error { var runtimeLogCode: RuntimeLog.Code { get } }
