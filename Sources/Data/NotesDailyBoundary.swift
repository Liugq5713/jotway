import Foundation
import CryptoKit

struct NotesDailyScope: Codable, Equatable, Sendable {
    let folderID: String
    let day: String
    let timeZoneID: String

    static func current(folderID: String, at date: Date = Date(), timeZone: TimeZone = .current) -> Self {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return .init(folderID: folderID,
            day: String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!),
            timeZoneID: timeZone.identifier)
    }
}

/// Complete-body and ordered-region fingerprints. No original or generated text is persisted.
/// Exact whitespace is significant: an external edit must not become permission to overwrite.
struct NotesDailyBoundary: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case title, metadata, original, generated }
    struct Part: Equatable, Sendable {
        let kind: Kind
        var entryID: String? = nil
        let text: String
    }
    struct Region: Codable, Equatable, Sendable {
        let kind: Kind
        let entryID: String?
        let length: Int
        let hash: String
    }
    let formatVersion: Int
    let bodyHash: String
    let bodyLength: Int
    let regions: [Region]

    init(parts: [Part]) {
        let values = parts.map { Self.normalizedLines($0.text) }
        let body = values.joined()
        formatVersion = 1
        bodyHash = Self.hash(body)
        bodyLength = body.count
        regions = zip(parts, values).map { part, text in
            Region(kind: part.kind, entryID: part.entryID, length: text.count, hash: Self.hash(text))
        }
    }

    func extract(from text: String) -> [Part]? {
        let body = Self.normalizedLines(text)
        guard formatVersion == 1, body.count == bodyLength, Self.hash(body) == bodyHash else { return nil }
        var cursor = body.startIndex
        var parts: [Part] = []
        var entries = Set<String>()
        for region in regions {
            guard region.length >= 0,
                  let end = body.index(cursor, offsetBy: region.length, limitedBy: body.endIndex) else { return nil }
            let value = String(body[cursor..<end])
            guard Self.hash(value) == region.hash else { return nil }
            if region.kind == .original {
                guard let id = region.entryID, !id.isEmpty, entries.insert(id).inserted else { return nil }
            } else if region.entryID != nil { return nil }
            parts.append(.init(kind: region.kind, entryID: region.entryID, text: value))
            cursor = end
        }
        guard cursor == body.endIndex else { return nil }
        return parts
    }

    static func normalizedLines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
