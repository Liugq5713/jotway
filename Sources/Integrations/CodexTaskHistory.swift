import Foundation
import Observation

struct CodexTaskRecord: Codable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case running, completed, failed, unknown

        var localizationKey: String { "action.codex.status.\(rawValue)" }
        var systemImage: String {
            switch self {
            case .running: "clock"
            case .completed: "checkmark.circle"
            case .failed: "exclamationmark.circle"
            case .unknown: "questionmark.circle"
            }
        }
    }

    let id: UUID
    let title: String
    let createdAt: Date
    var status: Status
    var threadID: String?
    var conversationName: String?

    var displayTitle: String { conversationName ?? title }

    var conversationURL: URL? {
        guard let threadID, UUID(uuidString: threadID) != nil else { return nil }
        return URL(string: "codex://threads/\(threadID)")
    }
}

/// Reads Jotway's task folders and names for their known conversation IDs through the public protocol.
/// Jotway never opens Codex's private database or credential files.
@MainActor @Observable
final class CodexTaskHistory {
    static let shared = CodexTaskHistory(directory: CodexTaskRunner.tasksDirectory)
    private(set) var recentTasks: [CodexTaskRecord] = []
    private(set) var isLoading = false
    private(set) var loadFailed = false
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var records: [UUID: CodexTaskRecord] = [:]
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var loadTask: Task<[CodexTaskRecord], Error>?
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?
    @ObservationIgnored private var isRefreshingNames = false
    @ObservationIgnored private var lastNameRefresh: [String: Date] = [:]

    init(directory: URL) { self.directory = directory }

    func loadIfNeeded() async {
        guard !loaded else { return }
        if loadTask == nil {
            isLoading = true
            let directory = directory
            loadTask = Task.detached(priority: .utility) { try Self.readRecent(in: directory) }
        }
        guard let loadTask else { return }
        do {
            let saved = try await loadTask.value
            guard !loaded else { return }
            for record in saved where records[record.id] == nil { records[record.id] = record }
            loaded = true
            loadFailed = false
            refreshRecent()
        } catch {
            loadFailed = true
        }
        self.loadTask = nil
        isLoading = false
    }

    func start(id: UUID, prompt: String) async {
        let createdAt = Date()
        await loadIfNeeded()
        // A short, single-line label is enough to identify the task; do not duplicate its full prompt.
        let title = String(prompt.prefix(240)).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        await save(CodexTaskRecord(id: id, title: String(title.prefix(120)), createdAt: createdAt, status: .running))
    }

    func attachThread(_ threadID: String, to id: UUID) async {
        guard var record = records[id], record.threadID != threadID else { return }
        record.threadID = threadID
        await save(record)
    }

    func finish(_ id: UUID, status: CodexTaskRecord.Status) async {
        guard var record = records[id] else { return }
        record.status = status
        await save(record)
    }

    func setConversationName(_ name: String?, for id: UUID, threadID: String) async {
        guard var record = records[id], record.threadID == threadID else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed?.isEmpty == false ? trimmed : nil
        guard record.conversationName != name else { return }
        record.conversationName = name
        await save(record)
    }

    func refreshConversationNames() async {
        await loadIfNeeded()
        guard !Task.isCancelled, !isRefreshingNames else { return }
        let now = Date()
        let requested = recentTasks.filter {
            guard let threadID = $0.threadID, $0.conversationURL != nil else { return false }
            return now.timeIntervalSince(lastNameRefresh[threadID] ?? .distantPast) >= 30
        }
        guard !requested.isEmpty else { return }
        isRefreshingNames = true
        defer { isRefreshingNames = false }
        for record in requested { if let threadID = record.threadID { lastNameRefresh[threadID] = now } }
        let names = await CodexTaskRunner.shared.readThreadNames(requested.compactMap(\.threadID))
        guard !Task.isCancelled else { return }
        for name in names {
            guard let original = requested.first(where: { $0.threadID == name.threadID }),
                  records[original.id]?.conversationName == original.conversationName else { continue }
            // Do not overwrite a newer name event with a response from an older read.
            await setConversationName(name.name, for: original.id, threadID: name.threadID)
        }
    }

    func taskDirectory(for record: CodexTaskRecord) -> URL {
        directory.appendingPathComponent(record.id.uuidString, isDirectory: true)
    }

    private func save(_ record: CodexTaskRecord) async {
        records[record.id] = record
        refreshRecent()
        let target = taskDirectory(for: record).appendingPathComponent(".jotway-task.json")
        // Metadata failure must never change execution success or cause a task to be retried.
        let previousWrite = pendingWrite
        let write = Task.detached(priority: .utility) {
            await previousWrite?.value
            guard let data = try? JSONEncoder().encode(record) else { return }
            try? data.write(to: target, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        }
        pendingWrite = write
        await write.value
    }

    private func refreshRecent() {
        recentTasks = Array(records.values.sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString > $1.id.uuidString : $0.createdAt > $1.createdAt
        }.prefix(5))
        let visible = Set(recentTasks.map(\.id))
        records = records.filter { visible.contains($0.key) || $0.value.status == .running }
    }

    nonisolated private static func readRecent(in directory: URL) throws -> [CodexTaskRecord] {
        let files = FileManager.default
        guard files.fileExists(atPath: directory.path) else { return [] }
        let folders = try files.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey], options: [.skipsHiddenFiles])
            .compactMap { url -> (URL, UUID, Date)? in
                guard let id = UUID(uuidString: url.lastPathComponent),
                      let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey]),
                      values.isDirectory == true else { return nil }
                return (url, id, values.creationDate ?? .distantPast)
            }.sorted { $0.2 == $1.2 ? $0.1.uuidString > $1.1.uuidString : $0.2 > $1.2 }
        var result: [CodexTaskRecord] = []
        for (folder, id, date) in folders {
            if let data = try? Data(contentsOf: folder.appendingPathComponent(".jotway-task.json")),
               var record = try? JSONDecoder().decode(CodexTaskRecord.self, from: data), record.id == id {
                // A prior process cannot still report live progress after a restart.
                if record.status == .running { record.status = .unknown }
                result.append(record)
            } else {
                // Older tasks have no label metadata. Keep their existing result/shortcut reachable.
                let shortcut = folder.appendingPathComponent("Open in Codex.webloc")
                let data = try? Data(contentsOf: shortcut)
                let property = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) }
                let link = (property as? [String: String])?["URL"].flatMap(URL.init(string:))
                let threadID = link.flatMap { url -> String? in
                    guard url.scheme == "codex", url.host == "threads",
                          UUID(uuidString: url.lastPathComponent) != nil else { return nil }
                    return url.lastPathComponent
                }
                let hasResult = files.fileExists(atPath: folder.appendingPathComponent("result.md").path)
                guard hasResult || threadID != nil else { continue }
                result.append(CodexTaskRecord(id: id, title: "", createdAt: date,
                    status: .completed, threadID: threadID))
            }
            if result.count == 5 { break }
        }
        return result
    }
}
