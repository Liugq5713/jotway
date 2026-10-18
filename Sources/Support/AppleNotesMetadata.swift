import AppKit
import Carbon

/// Read only metadata, never `properties` (which also fetches note bodies).
/// Rechecking IDs prevents independently returned columns from joining different notes
/// when the user edits the folder while a batch is being read.
enum AppleNotesMetadata {
    static let batchSize = 40
    enum Failure: Error { case unsupportedResponse }

    static func read(folderID: String, count: Int,
                     property: (OSType, ClosedRange<Int>) throws -> NSAppleEventDescriptor,
                     progress: (@MainActor @Sendable (Int, Int) async -> Void)?) async throws -> [NotesSource] {
        var sources: [NotesSource] = []
        await progress?(0, count)
        for start in stride(from: 1, through: count, by: batchSize) {
            try Task.checkCancellation()
            let range = start...min(start + batchSize - 1, count)
            func values(_ code: OSType) throws -> [NSAppleEventDescriptor] {
                let result = try property(code, range)
                if range.count == 1, result.descriptorType != DescType(typeAEList) { return [result] }
                guard result.descriptorType == DescType(typeAEList), result.numberOfItems == range.count else {
                    throw Failure.unsupportedResponse
                }
                return try (1...result.numberOfItems).map {
                    guard let item = result.atIndex($0) else { throw Failure.unsupportedResponse }
                    return item
                }
            }
            func strings(_ code: OSType) throws -> [String] {
                try values(code).map {
                    guard let value = $0.stringValue else { throw Failure.unsupportedResponse }
                    return value
                }
            }
            let ids = try strings(0x49442020) // ID
            let titles = try strings(0x706E616D) // pnam
            let created = try values(0x61736364) // ascd
            let modified = try values(0x61736D6F) // asmo
            let locked = try values(0x70777072) // pwpr
            let shared = try values(0x73687264) // shrd
            guard try strings(0x49442020) == ids, Set(ids).count == ids.count else {
                throw NotesReadError.stale
            }
            for offset in ids.indices {
                guard !ids[offset].isEmpty, let creation = created[offset].dateValue,
                      let modification = modified[offset].dateValue else { throw Failure.unsupportedResponse }
                sources.append(.init(id: ids[offset], folderID: folderID, title: titles[offset],
                    created: creation, modified: modification,
                    locked: locked[offset].booleanValue, shared: shared[offset].booleanValue))
            }
            await progress?(sources.count, count)
        }
        guard Set(sources.map(\.id)).count == sources.count else { throw NotesReadError.stale }
        return sources
    }
}
