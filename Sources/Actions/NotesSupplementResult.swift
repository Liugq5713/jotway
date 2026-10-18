import Foundation

/// Content and execution diagnostics travel separately; only the deadline winner is adopted.
struct NotesSupplementResult: Sendable {
    enum Preparation: String, Codable, Sendable {
        case disabled, generated, validEmpty = "valid_empty"
        // Decode existing diagnostics without producing new history results.
        case legacyHistoryOnly = "history_only"
        case configurationMissing = "configuration_missing", invalidOutput = "invalid_output"
        case providerError = "provider_error", timeout, stale, cancelled
    }
    enum Rejection: String, Error, Codable, Sendable { case schema, cardinality, length, source, evidence, duplicate }
    enum Adoption: String, Codable, Sendable {
        case applied, empty, renderFiltered = "render_filtered", provenanceUnavailable = "provenance_unavailable"
    }

    struct Report: Codable, Sendable {
        var preparation: Preparation? = nil
        var rejection: Rejection? = nil
        var itemCount: Int? = nil
        var adoptedItemCount: Int? = nil
        var adoption: Adoption? = nil

        var bounded: Self {
            var value = self
            value.itemCount = itemCount.map { min(max(0, $0), NotesSupplement.maximumItemCount) }
            value.adoptedItemCount = adoptedItemCount.map { min(max(0, $0), NotesSupplement.maximumItemCount) }
            return value
        }
    }

    var supplement: NotesSupplement = .empty
    var report = Report()

    static func empty(_ reason: Preparation) -> Self {
        .init(report: .init(preparation: reason))
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
