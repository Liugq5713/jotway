import CryptoKit
import Darwin
import Foundation
import GRDB

/// Runs before App/property-wrapper construction. Never opens a source database for writing.
struct StorageMigration {
    enum Failure: String, Error, LocalizedError {
        case unsafePath, inaccessible, sourceRunning, conflictingState, invalidCopy, invalidJournal, preferences
        var errorDescription: String? { L10n.text("migration.error.\(rawValue)") }
    }
    enum Phase: String, Codable, CaseIterable { case discovered, staged, dataPromoted, preferencesCommitted, complete }
    struct Paths {
        let home: URL
        let bundleID: String
        let container: URL
        var source: URL { container.appendingPathComponent("Data/Library/Application Support/Jotway", isDirectory: true) }
        var sourcePreferences: URL { container.appendingPathComponent("Data/Library/Preferences/\(bundleID).plist") }
        var target: URL { home.appendingPathComponent("Library/Application Support/Jotway", isDirectory: true) }
        var control: URL { home.appendingPathComponent("Library/Application Support/.Jotway-migration", isDirectory: true) }
        init(home: URL, bundleID: String = StorageLocation.bundleID, container: URL? = nil) {
            self.home = StorageLocation.lexicalURL(home)
            self.bundleID = bundleID
            self.container = container ?? home.appendingPathComponent("Library/Containers/\(bundleID)", isDirectory: true)
        }
    }
    private struct CredentialEntry: Decodable {
        let version: Int
        let key: String?
    }
    private struct Journal: Codable {
        let version: Int
        let id: UUID
        let source: String
        let target: String
        let sourceDigest: String
        let sourcePreferencesDigest: String
        let initialPreferencesDigest: String
        let hasSource: Bool
        var stagedDigest: String?
        var phase: Phase
    }
    let paths: Paths
    let sourceIsRunning: () -> Bool
    let readPreferences: () -> [String: Any]
    let writePreferences: ([String: Any]) throws -> Void
    var afterPhase: (Phase) throws -> Void = { _ in }

    func run() throws {
        // Resume the explicitly selected owned container recorded by this journal.
        let journalPath = paths.control.appendingPathComponent("journal.json")
        if try exists(journalPath) {
            let data = try safeData(journalPath, limit: 65_536)
            if let saved = try? JSONDecoder().decode(Journal.self, from: data), saved.source != paths.source.path {
                let source = URL(fileURLWithPath: saved.source)
                let container = source.deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent()
                let recovered = Paths(home: paths.home, bundleID: paths.bundleID, container: container)
                guard container.lastPathComponent == paths.bundleID, recovered.source.path == saved.source,
                      saved.target == paths.target.path else { throw Failure.invalidJournal }
                try requireSafe(container, inside: paths.home, allowMissing: saved.phase == .complete)
                var recovery = StorageMigration(paths: recovered, sourceIsRunning: sourceIsRunning,
                    readPreferences: readPreferences, writePreferences: writePreferences)
                recovery.afterPhase = afterPhase
                try recovery.run()
                return
            }
        }
        try requireSafe(paths.home, inside: paths.home)
        try requireSafe(paths.target, inside: paths.home, allowMissing: true)
        try requireSafe(paths.control, inside: paths.home, allowMissing: true)
        try FileManager.default.createDirectory(at: paths.control, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: paths.control.path)
        let lock = open(paths.control.appendingPathComponent("lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw Failure.inaccessible }
        defer { close(lock) }
        var lockInfo = stat()
        guard fstat(lock, &lockInfo) == 0, lockInfo.st_uid == getuid(),
              lockInfo.st_mode & S_IFMT == S_IFREG, lockInfo.st_nlink == 1 else { throw Failure.unsafePath }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw Failure.sourceRunning }
        defer { flock(lock, LOCK_UN) }
        let journalURL = paths.control.appendingPathComponent("journal.json")
        var journal: Journal
        if try exists(journalURL) {
            let data = try safeData(journalURL, limit: 65_536)
            guard let saved = try? JSONDecoder().decode(Journal.self, from: data), saved.version == 1,
                  saved.source == paths.source.path, saved.target == paths.target.path else { throw Failure.invalidJournal }
            journal = saved
            if journal.phase == .complete {
                guard try exists(paths.target) else { throw Failure.invalidJournal }
                return
            }
        } else {
            guard !sourceIsRunning() else { throw Failure.sourceRunning }
            let hasSource = try exists(paths.source)
            let prefs = try sourcePreferences()
            let hasOldState = hasSource || !prefs.isEmpty
            let hasTarget = try exists(paths.target)
            guard !(hasOldState && hasTarget) else { throw Failure.conflictingState }
            let current = readPreferences()
            guard prefs.isEmpty || current.isEmpty || NSDictionary(dictionary: prefs).isEqual(to: current) else {
                throw Failure.conflictingState
            }
            journal = Journal(version: 1, id: UUID(), source: paths.source.path, target: paths.target.path,
                sourceDigest: hasSource ? try manifest(paths.source) : "absent",
                sourcePreferencesDigest: try preferenceDigest(prefs),
                initialPreferencesDigest: try preferenceDigest(current), hasSource: hasSource,
                stagedDigest: nil, phase: .discovered)
            // An existing direct root with no legacy state is already established data.
            if hasTarget {
                try validateCopy(paths.target, normalize: false)
                journal.phase = .complete
            }
            try save(journal, at: journalURL)
            try afterPhase(journal.phase)
            if journal.phase == .complete { return }
        }
        try requireSafe(paths.container, inside: paths.home, allowMissing: true)
        guard !sourceIsRunning() else { throw Failure.sourceRunning }
        let staging = paths.control.appendingPathComponent("stage-" + journal.id.uuidString, isDirectory: true)
        let prefs = try sourcePreferences()
        func verifySourceSnapshot() throws {
            guard !sourceIsRunning() else { throw Failure.sourceRunning }
            let digest = try exists(paths.source) ? manifest(paths.source) : "absent"
            guard digest == journal.sourceDigest,
                  try preferenceDigest(sourcePreferences()) == journal.sourcePreferencesDigest else {
                throw Failure.conflictingState
            }
        }
        try verifySourceSnapshot()
        if journal.phase == .discovered {
            try requireSafe(staging, inside: paths.control, allowMissing: true)
            // Only this journal's unpromoted generated copy can be reconstructed after interruption.
            if try exists(staging) { try FileManager.default.removeItem(at: staging) }
            if journal.hasSource { try FileManager.default.copyItem(at: paths.source, to: staging) }
            else { try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false) }
            guard !sourceIsRunning(),
                  (journal.hasSource ? try manifest(paths.source) : "absent") == journal.sourceDigest else {
                throw Failure.conflictingState
            }
            if journal.hasSource, try manifest(staging) != journal.sourceDigest { throw Failure.invalidCopy }
            try validateCopy(staging, normalize: true)
            journal.stagedDigest = try manifest(staging)
            journal.phase = .staged
            try save(journal, at: journalURL); try afterPhase(.staged)
        }
        if journal.phase == .staged {
            try verifySourceSnapshot()
            let stagedExists = try exists(staging), targetExists = try exists(paths.target)
            guard stagedExists != targetExists else { throw Failure.conflictingState }
            let candidate = stagedExists ? staging : paths.target
            guard try manifest(candidate) == journal.stagedDigest else { throw Failure.invalidCopy }
            if stagedExists {
                try FileManager.default.moveItem(at: staging, to: paths.target)
                try syncDirectory(paths.target.deletingLastPathComponent())
                try syncDirectory(paths.control)
            }
            journal.phase = .dataPromoted
            try save(journal, at: journalURL); try afterPhase(.dataPromoted)
        }
        if journal.phase == .dataPromoted {
            try verifySourceSnapshot()
            guard try manifest(paths.target) == journal.stagedDigest else { throw Failure.conflictingState }
            let current = try preferenceDigest(readPreferences())
            guard current == journal.initialPreferencesDigest || current == journal.sourcePreferencesDigest else {
                throw Failure.conflictingState
            }
            if !prefs.isEmpty { try writePreferences(prefs) }
            let expected = prefs.isEmpty ? journal.initialPreferencesDigest : journal.sourcePreferencesDigest
            guard try preferenceDigest(readPreferences()) == expected else { throw Failure.preferences }
            journal.phase = .preferencesCommitted
            try save(journal, at: journalURL); try afterPhase(.preferencesCommitted)
        }
        if journal.phase == .preferencesCommitted {
            try verifySourceSnapshot()
            guard try manifest(paths.target) == journal.stagedDigest else { throw Failure.conflictingState }
            let expected = prefs.isEmpty ? journal.initialPreferencesDigest : journal.sourcePreferencesDigest
            guard try preferenceDigest(readPreferences()) == expected else { throw Failure.preferences }
            journal.phase = .complete
            try save(journal, at: journalURL); try afterPhase(.complete)
        }
    }

    private func sourcePreferences() throws -> [String: Any] {
        guard try exists(paths.sourcePreferences) else { return [:] }
        let data = try safeData(paths.sourcePreferences, limit: 8 * 1_048_576)
        guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw Failure.preferences
        }
        return result
    }

    private func preferenceDigest(_ preferences: [String: Any]) throws -> String {
        // XML property lists preserve booleans/types and sort dictionaries deterministically.
        let data = try PropertyListSerialization.data(fromPropertyList: preferences, format: .xml, options: 0)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func exists(_ url: URL) throws -> Bool {
        try requireSafe(url, inside: paths.home, allowMissing: true)
        var value = stat()
        if lstat(url.path, &value) == 0 { return true }
        if errno == ENOENT { return false }
        throw Failure.inaccessible
    }

    /// Inspect every ancestor without following links. Permission errors are never "fresh install".
    private func requireSafe(_ url: URL, inside root: URL, allowMissing: Bool = false) throws {
        let base = StorageLocation.lexicalURL(root).path, path = StorageLocation.lexicalURL(url).path
        guard path == base || path.hasPrefix(base + "/") else { throw Failure.unsafePath }
        var current = URL(fileURLWithPath: base, isDirectory: true)
        let suffix = path.dropFirst(base.count).split(separator: "/").map(String.init)
        for component in [Optional<String>.none] + suffix.map(Optional.some) {
            if let component { current.appendPathComponent(component) }
            var info = stat()
            if lstat(current.path, &info) != 0 {
                if allowMissing, errno == ENOENT { return }
                throw Failure.inaccessible
            }
            guard info.st_uid == getuid(), info.st_mode & S_IFMT != S_IFLNK else { throw Failure.unsafePath }
        }
    }

    private func safeData(_ url: URL, limit: Int) throws -> Data {
        try requireSafe(url, inside: paths.home)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.inaccessible }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1, info.st_size <= limit else { throw Failure.unsafePath }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        guard let data = try file.read(upToCount: limit + 1), data.count <= limit else { throw Failure.invalidCopy }
        return data
    }

    /// Hash relative names and bytes only; no source SQLite/credential reader is instantiated.
    private func manifest(_ root: URL) throws -> String {
        try requireSafe(root, inside: paths.home)
        var digest = SHA256()
        func visit(_ url: URL, relative: String) throws {
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_uid == getuid() else { throw Failure.inaccessible }
            digest.update(data: Data(relative.utf8))
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                digest.update(data: Data([0]))
                for name in try FileManager.default.contentsOfDirectory(atPath: url.path).sorted() {
                    try visit(url.appendingPathComponent(name), relative: relative + "/" + name)
                }
            case S_IFREG:
                guard info.st_nlink == 1 else { throw Failure.unsafePath }
                digest.update(data: Data([1]))
                let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
                guard fd >= 0 else { throw Failure.inaccessible }
                defer { close(fd) }
                let file = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
                while let bytes = try file.read(upToCount: 65_536), !bytes.isEmpty { digest.update(data: bytes) }
            default: throw Failure.unsafePath
            }
        }
        try visit(root, relative: "")
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func validateCopy(_ root: URL, normalize: Bool) throws {
        _ = try manifest(root)
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw Failure.invalidCopy
        }
        if normalize { try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path) }
        let entries = files.allObjects.compactMap { $0 as? URL }
        if normalize {
            for file in entries {
                let values = try file.resourceValues(forKeys: [.isDirectoryKey])
                try FileManager.default.setAttributes([.posixPermissions: values.isDirectory == true ? 0o700 : 0o600], ofItemAtPath: file.path)
            }
        }
        for file in entries where file.pathExtension == "sqlite" || file.deletingLastPathComponent().lastPathComponent == "Credentials" {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if normalize {
                try FileManager.default.setAttributes([.posixPermissions: values.isDirectory == true ? 0o700 : 0o600], ofItemAtPath: file.path)
            }
            if values.isRegularFile == true, file.pathExtension == "sqlite" {
                // Recovery/checkpoint belongs only to the copy. Source WAL/SHM remain byte-for-byte intact.
                var config = Configuration(); config.readonly = !normalize
                let db = try DatabaseQueue(path: file.path, configuration: config)
                defer { try? db.close() }
                let checks = try db.read { try String.fetchAll($0, sql: "PRAGMA integrity_check") }
                guard checks == ["ok"] else { throw Failure.invalidCopy }
            }
            if values.isRegularFile == true, file.deletingLastPathComponent().lastPathComponent == "Credentials" {
                let data = try safeData(file, limit: 16_384)
                guard let entry = try? JSONDecoder().decode(CredentialEntry.self, from: data),
                      entry.version == 1 else { throw Failure.invalidCopy }
                if let key = entry.key {
                    guard !key.isEmpty, key.utf8.count <= 4096,
                          key.unicodeScalars.allSatisfy({ (0x21...0x7e).contains($0.value) }) else { throw Failure.invalidCopy }
                }
            }
        }
    }

    private func save(_ journal: Journal, at url: URL) throws {
        try JSONEncoder().encode(journal).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.inaccessible }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw Failure.inaccessible }
        try syncDirectory(url.deletingLastPathComponent())
    }

    private func syncDirectory(_ url: URL) throws {
        let parent = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw Failure.inaccessible }
        defer { close(parent) }
        guard fsync(parent) == 0 else { throw Failure.inaccessible }
    }
}
