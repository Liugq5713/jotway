import Foundation
import Observation

/// One read-only user-script probe shared by display, submission and history gates.
@MainActor @Observable
final class CodexAvailability {
    enum State: Equatable, Sendable {
        case checking, cliMissing, needsSetup, ready, checkFailed
        var messageKey: String {
            switch self {
            case .checking: "action.codex.checking"
            case .cliMissing: "action.codex.cli_missing"
            case .needsSetup: "action.codex.missing"
            case .ready: "action.codex.ready"
            case .checkFailed: "action.codex.check_failed"
            }
        }
    }
    static let shared = CodexAvailability()
    static let probeName = "jotway-codex-check-v1.sh"
    typealias Probe = @Sendable (URL) async throws -> Data
    private(set) var state: State = .needsSetup
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    private let scriptsDirectory: @MainActor () -> URL?
    private let probe: Probe
    private let timeout: Duration
    private var generation = 0
    @ObservationIgnored private var flight: Flight?

    private final class Flight {
        let generation: Int
        var result: State?
        var waiters: [CheckedContinuation<State, Never>] = []
        var timer: Task<Void, Never>?
        init(generation: Int) { self.generation = generation }
    }

    init(scriptsDirectory: @escaping @MainActor () -> URL? = {
        StorageLocation.applicationScripts()
    }, timeout: Duration = .seconds(3), probe: @escaping Probe = CodexAvailability.executeProbe) {
        self.scriptsDirectory = scriptsDirectory; self.timeout = timeout; self.probe = probe
        refreshFiles()
    }

    var helperURL: URL? { scriptsDirectory()?.appendingPathComponent(CodexTaskRunner.helperName) }
    private var probeURL: URL? { scriptsDirectory()?.appendingPathComponent(Self.probeName) }
    private func executable(_ url: URL?) -> Bool {
        guard let url else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: url.path)
    }
    private func publish(_ next: State) {
        guard next != state else { return }
        state = next; onChange?()
    }
    /// Synchronous confirmation checks inspect files only, never launch a process.
    func refreshFiles() {
        if !executable(probeURL) || !executable(helperURL) {
            if state != .needsSetup { generation &+= 1 }
            publish(.needsSetup)
        }
    }
    func invalidate() {
        generation &+= 1
        publish(.checkFailed)
        refreshFiles()
    }
    func requestRefresh(invalidate: Bool = false) {
        if invalidate { self.invalidate() }
        Task { _ = await refresh() }
    }
    /// A confirmation never adopts a probe that began before that confirmation.
    func requireReady() async throws {
        try Task.checkCancellation()
        let result = await refresh(fresh: true)
        try Task.checkCancellation()
        guard result == .ready else { throw ActionFailure(localized: result.messageKey, code: .unavailable) }
    }
    func requireCurrentReady() throws {
        refreshFiles()
        guard state == .ready else { throw ActionFailure(localized: state.messageKey, code: .unavailable) }
    }
    func refresh(fresh: Bool = false) async -> State {
        refreshFiles()
        guard let url = probeURL, executable(url) else { return state }
        if let current = flight {
            let result = await wait(current)
            if !fresh { return result }
            // A timed-out NSUserUnixTask cannot be terminated; do not stack another process.
            guard flight == nil else { return .checkFailed }
            guard !Task.isCancelled else { return .checkFailed }
        }
        let current = Flight(generation: generation)
        flight = current
        // Rechecking the same ready configuration must not invalidate its own preparation.
        if !(fresh && state == .ready) { publish(.checking) }
        current.timer = Task { [weak self, weak current] in
            do { try await Task.sleep(for: self?.timeout ?? .seconds(3)) } catch { return }
            guard let self, let current, self.flight === current else { return }
            self.finish(current, result: .checkFailed, exited: false)
        }
        let probe = probe
        Task { [weak self, current] in
            let result: State
            do { result = Self.parse(try await probe(url)) }
            catch { result = .checkFailed }
            self?.finish(current, result: result, exited: true)
        }
        return await wait(current)
    }
    private func wait(_ current: Flight) async -> State {
        if let result = current.result { return result }
        return await withCheckedContinuation { current.waiters.append($0) }
    }
    private func finish(_ current: Flight, result: State, exited: Bool) {
        guard flight === current else { return }
        if exited { flight = nil; current.timer?.cancel() }
        guard current.result == nil else { return } // Ignore success arriving after timeout.
        let next: State
        if current.generation != generation { next = state == .needsSetup ? .needsSetup : .checkFailed }
        else if !executable(probeURL) { next = .needsSetup }
        else if result == .ready && !executable(helperURL) { next = .needsSetup }
        else { next = result }
        current.result = next
        publish(next)
        let waiters = current.waiters; current.waiters = []
        waiters.forEach { $0.resume(returning: next) }
    }
    nonisolated static func parse(_ data: Data) -> State {
        guard data.count <= 1024 else { return .checkFailed }
        switch String(data: data, encoding: .utf8) {
        case "jotway-codex-check-v1 present\n": return .ready
        case "jotway-codex-check-v1 missing\n": return .cliMissing
        default: return .checkFailed
        }
    }
    nonisolated static func executeProbe(_ url: URL) async throws -> Data {
        let task = try NSUserUnixTask(url: url)
        let output = Pipe()
        task.standardOutput = output.fileHandleForWriting
        // Drain without retaining more than the fixed protocol limit. stderr remains /dev/null.
        let reader = Task.detached(priority: .utility) {
            defer { try? output.fileHandleForReading.close() }
            var result = Data()
            while let chunk = try output.fileHandleForReading.read(upToCount: 1024), !chunk.isEmpty {
                if result.count <= 1024 { result.append(chunk.prefix(1025 - result.count)) }
            }
            return result
        }
        do { try await task.execute(withArguments: []) }
        catch {
            try? output.fileHandleForWriting.close()
            _ = try? await reader.value
            throw error
        }
        try? output.fileHandleForWriting.close()
        return try await reader.value
    }
}
