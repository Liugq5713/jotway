import Foundation
import CryptoKit
import GRDB
import ImageIO
import UniformTypeIdentifiers

struct ClipboardEntry: Identifiable, Sendable, Equatable {
    let id: String
    let type: String
    let digest: String
    let text: String
    let thumbnail: Data?
    let width: Int
    let height: Int
    let ocrState: String
    let recognizedText: String

    var isImage: Bool { type != "public.utf8-plain-text" }
    func matches(_ query: String) -> Bool {
        let content = (isImage ? recognizedText : text).lowercased()
        return query.lowercased().split(whereSeparator: \.isWhitespace).allSatisfy { content.contains($0) }
    }
}

struct ClipboardPayload: Sendable {
    let type: String
    let data: Data
    var digest: String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

enum ClipboardFailure: Error, Equatable {
    case tooLarge, invalidImage, unavailable, stale, copyFailed, recognitionFailed
    var key: String {
        switch self {
        case .tooLarge: "clipboard.too_large"
        case .invalidImage: "clipboard.invalid_image"
        case .unavailable: "clipboard.storage_failed"
        case .stale: "clipboard.item_unavailable"
        case .copyFailed: "clipboard.copy_failed"
        case .recognitionFailed: "clipboard.ocr_failed"
        }
    }
}

/// Owns the history database independently of operation records. All image work and SQL
/// execute on this actor, never on the UI actor. List reads exclude original image blobs.
actor ClipboardHistoryStore {
    static let textLimit = 1_048_576
    static let imageLimit = 20 * 1_048_576
    static let pixelLimit = 40_000_000
    private let url: URL
    private let itemLimit: Int
    private let byteLimit: Int
    private var queue: DatabaseQueue?
    private var generation: UUID?

    init(url: URL, itemLimit: Int = 200, byteLimit: Int = 200 * 1_048_576) {
        self.url = url
        self.itemLimit = itemLimit
        self.byteLimit = byteLimit
    }

    func begin(_ generation: UUID) throws {
        self.generation = generation
        let db = try database()
        try db.write { db in
            try db.execute(sql: "UPDATE clips SET ocrState = 'pending' WHERE ocrState = 'processing'")
        }
    }

    func invalidate(_ generation: UUID) { self.generation = generation }

    private func database() throws -> DatabaseQueue {
        if let queue { return queue }
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA secure_delete = ON")
        }
        let value = try DatabaseQueue(path: url.path, configuration: configuration)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_clipboard") { db in
            try db.execute(sql: """
                CREATE TABLE clips (
                    id TEXT PRIMARY KEY, type TEXT NOT NULL, digest TEXT NOT NULL,
                    payload BLOB NOT NULL, text TEXT NOT NULL, thumbnail BLOB,
                    width INTEGER NOT NULL, height INTEGER NOT NULL, copiedAt DOUBLE NOT NULL,
                    ocrState TEXT NOT NULL, recognizedText TEXT NOT NULL DEFAULT '',
                    ocrVersion INTEGER NOT NULL DEFAULT 1, bytes INTEGER NOT NULL
                );
                CREATE INDEX clips_recent ON clips(copiedAt DESC);
                CREATE INDEX clips_digest ON clips(type, digest);
                """)
        }
        try migrator.migrate(value)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        queue = value
        return value
    }

    func entries() throws -> [ClipboardEntry] {
        try database().read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, type, digest, text, thumbnail, width, height, ocrState, recognizedText
                FROM clips ORDER BY copiedAt DESC, id ASC
                """).map { row in
                    ClipboardEntry(id: row["id"], type: row["type"], digest: row["digest"],
                        text: row["text"], thumbnail: row["thumbnail"], width: row["width"],
                        height: row["height"], ocrState: row["ocrState"], recognizedText: row["recognizedText"])
                }
        }
    }

    func capture(_ payload: ClipboardPayload, generation: UUID, at date: Date = Date()) throws {
        guard self.generation == generation else { throw ClipboardFailure.stale }
        let image = payload.type != "public.utf8-plain-text"
        guard payload.data.count <= (image ? Self.imageLimit : Self.textLimit) else { throw ClipboardFailure.tooLarge }
        var thumbnail: Data?
        var width = 0, height = 0
        let text = image ? "" : String(decoding: payload.data, as: UTF8.self)
        if image {
            let value = try Self.imagePreview(payload.data)
            thumbnail = value.data; width = value.width; height = value.height
        } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        let digest = payload.digest
        try database().write { db in
            let candidates = try Row.fetchAll(db, sql: "SELECT id, payload FROM clips WHERE type = ? AND digest = ?",
                                              arguments: [payload.type, digest])
            if let existing = candidates.first(where: { ( $0["payload"] as Data) == payload.data }) {
                let id: String = existing["id"]
                try db.execute(sql: "UPDATE clips SET copiedAt = ? WHERE id = ?", arguments: [date.timeIntervalSince1970, id])
            } else {
                try db.execute(sql: """
                    INSERT INTO clips (id,type,digest,payload,text,thumbnail,width,height,copiedAt,ocrState,bytes)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?)
                    """, arguments: [UUID().uuidString, payload.type, digest, payload.data, text,
                        thumbnail, width, height, date.timeIntervalSince1970, image ? "pending" : "none",
                        payload.data.count + text.utf8.count + (thumbnail?.count ?? 0)])
            }
            try prune(db)
        }
    }

    private func prune(_ db: GRDB.Database) throws {
        let rows = try Row.fetchAll(db, sql: "SELECT id, bytes FROM clips ORDER BY copiedAt DESC, id ASC")
        var total = 0
        for (index, row) in rows.enumerated() {
            let bytes: Int = row["bytes"]
            total += bytes
            if index >= itemLimit || total > byteLimit {
                let id: String = row["id"]
                try db.execute(sql: "DELETE FROM clips WHERE id = ?", arguments: [id])
            }
        }
    }

    func payload(for entry: ClipboardEntry, generation: UUID) throws -> ClipboardPayload {
        guard self.generation == generation else { throw ClipboardFailure.stale }
        guard let row = try database().read({ db in
            try Row.fetchOne(db, sql: "SELECT type, payload FROM clips WHERE id = ? AND digest = ?",
                             arguments: [entry.id, entry.digest])
        }) else { throw ClipboardFailure.stale }
        let value = ClipboardPayload(type: row["type"], data: row["payload"])
        guard value.digest == entry.digest else { throw ClipboardFailure.stale }
        return value
    }

    func updateOCR(_ entry: ClipboardEntry, state: String, text: String = "", generation: UUID) throws {
        guard self.generation == generation else { throw ClipboardFailure.stale }
        guard text.utf8.count <= 32_768 else { throw ClipboardFailure.recognitionFailed }
        try database().write { db in
            try db.execute(sql: """
                UPDATE clips SET ocrState = ?, bytes = bytes - length(CAST(recognizedText AS BLOB)) + ?,
                    recognizedText = ? WHERE id = ? AND digest = ? AND ocrVersion = 1
                """, arguments: [state, text.utf8.count, text, entry.id, entry.digest])
            guard db.changesCount == 1 else { throw ClipboardFailure.stale }
            try prune(db)
        }
    }

    func clear(generation: UUID) throws {
        self.generation = generation
        if let queue { try queue.close() }
        queue = nil
        for path in [url.path, url.path + "-wal", url.path + "-shm", url.path + "-journal"] {
            if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
        }
        _ = try database()
    }

    private static func imagePreview(_ data: Data) throws -> (data: Data, width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw ClipboardFailure.invalidImage }
        guard width <= pixelLimit, height <= pixelLimit, width <= pixelLimit / height else { throw ClipboardFailure.tooLarge }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 160]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ClipboardFailure.invalidImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw ClipboardFailure.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ClipboardFailure.invalidImage }
        return (output as Data, width, height)
    }
}
