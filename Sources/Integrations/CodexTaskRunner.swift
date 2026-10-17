import Darwin
import Foundation

/// Keeps the existing user-installed script boundary and login ownership.
@MainActor
final class CodexTaskRunner {
    struct Result: Sendable {
        let threadID: String
        let output: URL
        let conversationURL: URL
    }

    static let shared = CodexTaskRunner()
    static let helperName = "jotway-codex-v2.sh"
    private var running: [UUID: URL] = [:]

    static var tasksDirectory: URL {
        StorageLocation.appSupport.appendingPathComponent("Codex Tasks", isDirectory: true)
    }

    static var helperURL: URL? {
        guard let directory = StorageLocation.applicationScripts() else { return nil }
        return directory.appendingPathComponent(helperName)
    }

    func run(prompt: String, availability: CodexAvailability = .shared) async throws -> Result {
        try Task.checkCancellation()
        try availability.requireCurrentReady()
        guard let helper = availability.helperURL else {
            throw ActionFailure(localized: "action.codex.missing", code: .unavailable)
        }
        let id = UUID()
        let directory = Self.tasksDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let files = FileManager.default
        do {
            try files.createDirectory(at: directory, withIntermediateDirectories: true,
                                      attributes: [.posixPermissions: 0o700])
        } catch {
            throw ActionFailure(localized: "action.codex.storage_failed", code: .storage)
        }
        await CodexTaskHistory.shared.start(id: id, prompt: prompt)
        do {
            let result = try await execute(prompt: prompt, id: id, directory: directory, helper: helper)
            await CodexTaskHistory.shared.finish(id, status: .completed)
            return result
        } catch {
            let outcome = ActionFailure.presentation(for: error).executionOutcome
            await CodexTaskHistory.shared.finish(id,
                status: outcome == .unknown || error is CancellationError ? .unknown : .failed)
            throw error
        }
    }

    private func execute(prompt: String, id: UUID, directory: URL, helper: URL) async throws -> Result {
        let cancelURL = directory.appendingPathComponent("cancel")
        let files = FileManager.default
        try Task.checkCancellation()
        let task: NSUserUnixTask
        do { task = try NSUserUnixTask(url: helper) }
        catch { throw ActionFailure(localized: "action.codex.launch_failed", code: .helperLaunch) }

        let stdin = Pipe()
        let stdout = Pipe()
        // A disconnected server should throw from write(), not terminate Jotway with SIGPIPE.
        guard fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw ActionFailure(localized: "action.codex.launch_failed", code: .helperLaunch)
        }
        task.standardInput = stdin.fileHandleForReading
        task.standardOutput = stdout.fileHandleForWriting
        // The API's default stderr is /dev/null. Do not collect raw server diagnostics in Jotway logs.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
        let reader = Task.detached(priority: .utility) {
            defer {
                try? stdin.fileHandleForWriting.close()
                try? stdout.fileHandleForReading.close()
            }
            var session = CodexAppServerSession()
            do {
                try stdin.fileHandleForWriting.write(contentsOf: CodexAppServerSession.initialize(version: version))
                while let data = try CodexAppServerSession.readAvailable(from: stdout.fileHandleForReading) {
                    if !session.finished {
                        let previousThreadID = session.threadID
                        let previousNameRevision = session.threadNameRevision
                        try session.consume(data, prompt: prompt, directory: directory) {
                            try stdin.fileHandleForWriting.write(contentsOf: $0)
                        }
                        if let threadID = session.threadID, threadID != previousThreadID {
                            await CodexTaskHistory.shared.attachThread(threadID, to: id)
                        }
                        if let threadID = session.threadID, session.threadNameRevision != previousNameRevision {
                            await CodexTaskHistory.shared.setConversationName(session.threadName, for: id, threadID: threadID)
                        }
                        if session.finished { try? stdin.fileHandleForWriting.close() }
                    }
                }
                if !session.finished { session.connectionFailed() }
            } catch {
                if !session.completed { session.connectionFailed() }
                Self.requestCancellation(at: cancelURL)
            }
            // A failed turn/start write can still leave a valid thread worth inspecting.
            if let threadID = session.threadID {
                await CodexTaskHistory.shared.attachThread(threadID, to: id)
                if session.threadNameRevision > 0 {
                    await CodexTaskHistory.shared.setConversationName(session.threadName, for: id, threadID: threadID)
                }
            }
            return session
        }
        running[id] = cancelURL
        defer { running.removeValue(forKey: id) }
        return try await withTaskCancellationHandler {
            // The protocol confirms completion; a later shutdown error must not retry completed work.
            try? await task.execute(withArguments: [directory.path])
            // Release the parent's writer after the script finishes, allowing the reader to reach EOF.
            try? stdout.fileHandleForWriting.close()
            try? stdin.fileHandleForReading.close()
            let session = await reader.value
            try Task.checkCancellation()
            guard session.completed, !session.protocolFailed, let threadID = session.threadID,
                  let conversationURL = URL(string: "codex://threads/\(threadID)") else {
                throw ActionFailure(localized: session.submitted ? "action.codex.execution_uncertain" : "action.codex.failed",
                                    code: session.protocolFailed ? .disconnected : .processFailed,
                                    executionOutcome: session.submitted ? .unknown : .failed)
            }
            // Storage failure must not turn a completed remote turn into a retryable task.
            var output = directory.appendingPathComponent("result.md")
            do {
                try Data(session.finalText.utf8).write(to: output, options: .atomic)
                try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
            } catch {
                output = directory
            }
            // Only protocol metadata is saved. A shortcut failure must not retry an already completed task.
            if let shortcut = try? PropertyListSerialization.data(fromPropertyList: ["URL": conversationURL.absoluteString],
                                                                  format: .xml, options: 0) {
                try? shortcut.write(to: directory.appendingPathComponent("Open in Codex.webloc"), options: .atomic)
            }
            return Result(threadID: threadID, output: output, conversationURL: conversationURL)
        } onCancel: {
            // NSUserUnixTask has no terminate method. The helper watches this marker and owns its child.
            Self.requestCancellation(at: cancelURL)
        }
    }

    func cancelAll() {
        for url in running.values { Self.requestCancellation(at: url) }
    }

    /// Reads at most five known thread names through the existing user-installed helper.
    /// Closing the card or reaching the deadline stops this connection without affecting task execution.
    func readThreadNames(_ threadIDs: [String], availability: CodexAvailability = .shared) async -> [CodexThreadName] {
        guard !threadIDs.isEmpty, !Task.isCancelled else { return [] }
        guard (try? availability.requireCurrentReady()) != nil, let helper = availability.helperURL else { return [] }
        let id = UUID()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Jotway-Codex-Names-\(id.uuidString)")
        let cancelURL = directory.appendingPathComponent("cancel")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch { return [] }
        defer { try? FileManager.default.removeItem(at: directory) }
        guard let task = try? NSUserUnixTask(url: helper) else { return [] }
        let stdin = Pipe(), stdout = Pipe()
        guard fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { return [] }
        task.standardInput = stdin.fileHandleForReading
        task.standardOutput = stdout.fileHandleForWriting
        let reader = Task.detached(priority: .utility) {
            defer {
                try? stdin.fileHandleForWriting.close()
                try? stdout.fileHandleForReading.close()
            }
            var session = CodexThreadNamesSession(threadIDs: threadIDs)
            do {
                try stdin.fileHandleForWriting.write(contentsOf: CodexAppServerSession.initialize(version: "1"))
                while let data = try CodexAppServerSession.readAvailable(from: stdout.fileHandleForReading) {
                    if !session.finished {
                        try session.consume(data) { try stdin.fileHandleForWriting.write(contentsOf: $0) }
                        if session.finished { try? stdin.fileHandleForWriting.close() }
                    }
                }
            } catch { Self.requestCancellation(at: cancelURL) }
            return session.names
        }
        let deadline = Task.detached(priority: .utility) {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            Self.requestCancellation(at: cancelURL)
        }
        running[id] = cancelURL
        defer { deadline.cancel(); running.removeValue(forKey: id) }
        return await withTaskCancellationHandler {
            try? await task.execute(withArguments: [directory.path])
            try? stdout.fileHandleForWriting.close()
            try? stdin.fileHandleForReading.close()
            let names = await reader.value
            return Task.isCancelled ? [] : names
        } onCancel: { Self.requestCancellation(at: cancelURL) }
    }

    nonisolated private static func requestCancellation(at url: URL) {
        _ = FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: [.posixPermissions: 0o600])
    }
}
