import Foundation

/// Native ZIP snapshot and atomic publication, shared by the two local exports.
enum ZIPExport {
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Jotway.ZIPExport", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func write(directory root: URL, to destination: URL) throws {
        let scoped = destination.startAccessingSecurityScopedResource()
        defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
        // Foundation creates a ZIP for a directory; its temporary URL is valid only inside the accessor.
        var coordinationError: NSError?
        var output: Result<Void, Error>?
        NSFileCoordinator().coordinate(readingItemAt: root, options: .forUploading, error: &coordinationError) { archive in
            output = Result { try publish(archive, to: destination) }
        }
        if let coordinationError { throw coordinationError }
        guard let output else { throw failure(L10n.text("zip.generate_failed")) }
        try output.get()
    }

    /// Stage on the destination volume. Cancellation/failure leaves any existing final file intact.
    private static func publish(_ archive: URL, to destination: URL) throws {
        try Task.checkCancellation()
        let manager = FileManager.default
        let replacement = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                          appropriateFor: destination, create: true)
        defer { try? manager.removeItem(at: replacement) }
        let staged = replacement.appendingPathComponent("archive.zip")
        guard manager.createFile(atPath: staged.path, contents: nil) else {
            throw failure(L10n.text("zip.stage_failed"))
        }
        let input = try FileHandle(forReadingFrom: archive), output = try FileHandle(forWritingTo: staged)
        defer { try? input.close(); try? output.close() }
        while let bytes = try input.read(upToCount: 512 * 1024), !bytes.isEmpty {
            try Task.checkCancellation()
            try output.write(contentsOf: bytes)
        }
        try output.synchronize()
        try output.close()
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { target in
            result = Result {
                try Task.checkCancellation()
                if manager.fileExists(atPath: target.path) {
                    _ = try manager.replaceItemAt(target, withItemAt: staged)
                } else {
                    try manager.moveItem(at: staged, to: target)
                }
                // Publication is the commit point; a later cancellation must not report this complete ZIP as partial.
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw failure(L10n.text("zip.save_failed")) }
        try result.get()
    }
}
