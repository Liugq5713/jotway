import Foundation

/// Read compatibility for old content-free supplement diagnostics. No new producer uses this type.
enum LegacyNotesSupplementDiagnostics: Sendable {
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
            value.itemCount = itemCount.map { min(max(0, $0), 3) }
            value.adoptedItemCount = adoptedItemCount.map { min(max(0, $0), 3) }
            return value
        }
    }

}
