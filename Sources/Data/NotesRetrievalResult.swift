import Foundation

/// One scoped read, shared by generation and Search History. Counts never contain source identities.
struct NotesRetrievalResult: Sendable {
    static let maximumCandidates = 10
    static let maximumBytes = 8_000

    struct Counts: Codable, Equatable, Sendable {
        var rawChunkCount = 0
        var thresholdChunkCount = 0
        var eligibleSourceCount = 0
        var candidateCount = 0
        var candidateBytes = 0

        var bounded: Self {
            .init(rawChunkCount: min(max(0, rawChunkCount), 1_000_000),
                  thresholdChunkCount: min(max(0, thresholdChunkCount), 1_000_000),
                  eligibleSourceCount: min(max(0, eligibleSourceCount), 1_000_000),
                  candidateCount: min(max(0, candidateCount), NotesRetrievalResult.maximumCandidates),
                  candidateBytes: min(max(0, candidateBytes), NotesRetrievalResult.maximumBytes))
        }
    }

    struct Coverage: Codable, Equatable, Sendable {
        var searchable = 0
        var pending = 0
        var failed = 0
        var excluded = 0
        var hasSuccessfulSync = false

        var isIncomplete: Bool { !hasSuccessfulSync || pending > 0 || failed > 0 || excluded > 0 }
        var bounded: Self {
            .init(searchable: min(max(0, searchable), 1_000_000), pending: min(max(0, pending), 1_000_000),
                  failed: min(max(0, failed), 1_000_000), excluded: min(max(0, excluded), 1_000_000),
                  hasSuccessfulSync: hasSuccessfulSync)
        }
    }

    let hits: [NotesHistoryHit]
    let counts: Counts
    let coverage: Coverage
    let version: Int
}

/// Pure checks shared by retrieval, output validation and rendering.
enum NotesEvidence {
    static func comparisonText(_ text: String) -> String {
        text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        let a = comparisonText(lhs), b = comparisonText(rhs)
        return !a.isEmpty && !b.isEmpty && (a.contains(b) || b.contains(a))
    }

    static func hasEvidence(_ text: String) -> Bool {
        let withoutTags = text.replacingOccurrences(of: #"#[\p{L}\p{N}_-]+"#, with: "", options: .regularExpression)
        let value = comparisonText(withoutTags)
        let vague = ["可以尝试优化", "可以尝试这个优化", "尝试优化", "trytooptimize", "couldimprovethis"]
        return value.count >= 8 && !vague.contains(value)
    }
}
