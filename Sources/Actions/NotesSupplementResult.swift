import Foundation

/// Content and execution diagnostics travel separately; only the deadline winner is adopted.
struct NotesSupplementResult: Sendable {
    enum Preparation: String, Codable, Sendable {
        case disabled, generated, historyOnly = "history_only", validEmpty = "valid_empty"
        case configurationMissing = "configuration_missing", invalidOutput = "invalid_output"
        case providerError = "provider_error", timeout, stale, cancelled
    }
    enum Retrieval: String, Codable, Sendable { case disabled, unavailable, success, error, stale }
    enum Rejection: String, Error, Codable, Sendable { case schema, cardinality, length, source, evidence, duplicate }
    enum Adoption: String, Codable, Sendable {
        case applied, empty, renderFiltered = "render_filtered", provenanceUnavailable = "provenance_unavailable"
    }

    struct Report: Codable, Sendable {
        var retrieval: Retrieval? = nil
        var counts: NotesRetrievalResult.Counts? = nil
        var coverage: NotesRetrievalResult.Coverage? = nil
        var preparation: Preparation? = nil
        var rejection: Rejection? = nil
        var itemCount: Int? = nil
        var historyCount: Int? = nil
        var adoptedItemCount: Int? = nil
        var adoptedHistoryCount: Int? = nil
        var adoption: Adoption? = nil

        var bounded: Self {
            var value = self
            value.counts = counts?.bounded
            value.coverage = coverage?.bounded
            value.itemCount = itemCount.map { min(max(0, $0), NotesSupplement.maximumItemCount) }
            value.historyCount = historyCount.map { min(max(0, $0), NotesSupplement.maximumHistoryCount) }
            value.adoptedItemCount = adoptedItemCount.map { min(max(0, $0), NotesSupplement.maximumItemCount) }
            value.adoptedHistoryCount = adoptedHistoryCount.map { min(max(0, $0), NotesSupplement.maximumHistoryCount) }
            return value
        }
    }

    var supplement: NotesSupplement = .empty
    var report = Report()

    static func empty(_ reason: Preparation) -> Self {
        .init(report: .init(retrieval: reason == .disabled ? .disabled : nil, preparation: reason))
    }

    var outcome: RuntimeLog.Outcome {
        switch report.preparation {
        case .timeout: .timeout
        case .stale: .discarded
        case .cancelled: .cancelled
        case .configurationMissing, .providerError, .invalidOutput: .failed
        default: .success
        }
    }
}
