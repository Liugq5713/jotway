import Foundation

/// The app never loads Vision. Each job launches and reaps a disposable helper.
struct ClipboardTextRecognizer: Sendable {
    let executable: URL
    let timeout: TimeInterval

    init(executable: URL? = nil, timeout: TimeInterval = 60) {
        let binaryFolder = Bundle.main.executableURL?.deletingLastPathComponent() ?? Bundle.main.bundleURL
        let packaged = binaryFolder.deletingLastPathComponent().appendingPathComponent("Helpers/JotwayClipboardOCR")
        self.executable = executable ?? (FileManager.default.isExecutableFile(atPath: packaged.path)
            ? packaged : binaryFolder.appendingPathComponent("JotwayClipboardOCR"))
        self.timeout = timeout
    }

    func recognize(_ data: Data) async throws -> String {
        let job = ClipboardOCRProcess(executable: executable, timeout: timeout)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(with: Result { try job.run(data) })
                }
            }
        } onCancel: { job.cancel() }
    }
}

private final class ClipboardOCRProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let executable: URL
    private let timeout: TimeInterval
    private var process: Process?
    private var cancelled = false
    private var timeoutExpired = false

    init(executable: URL, timeout: TimeInterval) { self.executable = executable; self.timeout = timeout }

    func cancel(timedOut: Bool = false) {
        lock.lock()
        cancelled = true
        timeoutExpired = timeoutExpired || timedOut
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        lock.unlock()
    }

    func run(_ data: Data) throws -> String {
        guard data.count <= 20 * 1_048_576 else { throw ClipboardFailure.recognitionFailed }
        let child = Process()
        child.executableURL = executable
        child.arguments = []
        child.qualityOfService = .utility
        let pipe = Pipe()
        child.standardOutput = pipe
        child.standardError = FileHandle.nullDevice
        let input = Pipe()
        child.standardInput = input
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw ClipboardFailure.recognitionFailed
        }
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do { try child.run(); process = child; lock.unlock() }
        catch { lock.unlock(); throw ClipboardFailure.recognitionFailed }
        try? pipe.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
        // Drain stdout concurrently with stdin: either stream can exceed pipe capacity.
        let writer = DispatchGroup()
        writer.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { try? input.fileHandleForWriting.close(); writer.leave() }
            try? input.fileHandleForWriting.write(contentsOf: data)
        }
        let deadline = DispatchWorkItem { [weak self] in self?.cancel(timedOut: true) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer {
            deadline.cancel()
            if child.isRunning { cancel() }
            child.waitUntilExit()
            writer.wait()
            try? pipe.fileHandleForReading.close()
            lock.lock(); process = nil; lock.unlock()
        }
        var output = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 8192), !chunk.isEmpty {
            guard output.count + chunk.count <= 32_768 else { throw ClipboardFailure.recognitionFailed }
            output.append(chunk)
        }
        child.waitUntilExit()
        lock.lock(); let wasCancelled = cancelled; let didTimeout = timeoutExpired; lock.unlock()
        if didTimeout { throw ClipboardFailure.recognitionFailed }
        guard !wasCancelled else { throw CancellationError() }
        guard child.terminationStatus == 0, let text = String(data: output, encoding: .utf8) else {
            throw ClipboardFailure.recognitionFailed
        }
        return text
    }
}
