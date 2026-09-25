import Darwin
import Foundation

/// Jotway 自有凭证文件，只访问本应用的本地目录。
@MainActor
final class APIKeyStore {
    enum Provider: String, CaseIterable {
        case deepSeek = "deepseek", jev, moonshot
    }

    enum Failure: Error, LocalizedError, Equatable, RuntimeLogError {
        case inaccessible, corrupt

        var errorDescription: String? {
            switch self {
            case .inaccessible: L10n.text("credentials.inaccessible")
            case .corrupt: L10n.text("credentials.corrupt")
            }
        }

        var runtimeLogCode: RuntimeLog.Code { .configuration }
    }

    private struct Entry: Codable {
        var version = 1
        var key: String?
    }

    static let shared = APIKeyStore(
        directory: StorageLocation.appSupport.appendingPathComponent("Credentials", isDirectory: true)
    )

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func load(for provider: Provider) throws -> String? {
        try withDirectory { descriptor in
            try readEntry(for: provider, in: descriptor)?.key
        }
    }

    func save(_ key: String, for provider: Provider) throws {
        guard Self.isValid(key) else { throw Failure.corrupt }
        try withDirectory { try write(Entry(key: key), for: provider, in: $0) }
    }

    func remove(for provider: Provider) throws {
        try withDirectory { try write(Entry(key: nil), for: provider, in: $0) }
    }

    private static func isValid(_ key: String) -> Bool {
        !key.isEmpty && key.utf8.count <= 4096
            && key.unicodeScalars.allSatisfy { (0x21...0x7E).contains($0.value) }
    }

    private func withDirectory<T>(_ body: (Int32) throws -> T) throws -> T {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw Failure.inaccessible }
            defer { close(descriptor) }
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_uid == getuid(),
                  fchmod(descriptor, 0o700) == 0 else { throw Failure.inaccessible }
            return try body(descriptor)
        } catch let failure as Failure {
            throw failure
        } catch {
            // 不向界面、记录或日志传播包含路径或文件内容的底层错误。
            throw Failure.inaccessible
        }
    }

    private func readEntry(for provider: Provider, in directoryDescriptor: Int32) throws -> Entry? {
        let descriptor = openat(directoryDescriptor, "\(provider.rawValue).json", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw Failure.inaccessible
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              fchmod(descriptor, 0o600) == 0 else { throw Failure.inaccessible }
        guard info.st_size <= 16_384 else { throw Failure.corrupt }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        guard let data = try file.read(upToCount: 16_385), data.count <= 16_384,
              let entry = try? JSONDecoder().decode(Entry.self, from: data), entry.version == 1,
              entry.key.map(Self.isValid) ?? true else { throw Failure.corrupt }
        return entry
    }

    private func write(_ entry: Entry, for provider: Provider, in directoryDescriptor: Int32) throws {
        let name = "\(provider.rawValue).json"
        var info = stat()
        if fstatat(directoryDescriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid() else { throw Failure.inaccessible }
        } else if errno != ENOENT {
            throw Failure.inaccessible
        }

        let temporaryName = ".\(provider.rawValue)-\(UUID().uuidString).tmp"
        let descriptor = openat(directoryDescriptor, temporaryName,
                                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Failure.inaccessible }
        defer {
            close(descriptor)
            unlinkat(directoryDescriptor, temporaryName, 0)
        }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try file.write(contentsOf: JSONEncoder().encode(entry))
        guard fchmod(descriptor, 0o600) == 0, fsync(descriptor) == 0,
              renameat(directoryDescriptor, temporaryName, directoryDescriptor, name) == 0 else {
            throw Failure.inaccessible
        }
    }
}
