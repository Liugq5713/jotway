import Darwin
import Foundation

enum StorageLocation {
    static let bundleID = "com.liuguangqi.jotway"
    /// The account database is independent of Foundation's sandbox home redirection.
    static var userHome: URL? {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return nil }
        return lexicalURL(URL(fileURLWithPath: String(cString: directory), isDirectory: true))
    }
    /// Normalize components without Foundation resolving existing /private aliases.
    /// Security checks must inspect the same literal path before and after creation.
    static func lexicalURL(_ url: URL) -> URL {
        var components: [Substring] = []
        for part in url.path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { if !components.isEmpty { components.removeLast() } }
            else { components.append(part) }
        }
        return URL(fileURLWithPath: "/" + components.joined(separator: "/"), isDirectory: url.hasDirectoryPath)
    }
    static var appSupport: URL {
        guard let home = userHome else { preconditionFailure("User home unavailable before storage bootstrap") }
        return home.appendingPathComponent("Library/Application Support/Jotway", isDirectory: true)
    }
    static func applicationScripts(in home: URL? = userHome) -> URL? {
        home?.appendingPathComponent("Library/Application Scripts/\(bundleID)", isDirectory: true)
    }
}
