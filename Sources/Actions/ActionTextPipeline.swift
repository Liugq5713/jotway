import Foundation

/// Optional body rewriting. Scheduling is resolved separately from the original draft.
protocol ActionTextProcessor: Sendable {
    func process(_ text: String) async throws -> ProcessedText
}

/// Rewriting cannot supply or replace a destination or time.
struct ProcessedText: Sendable {
    var text: String
}

/// Rewriting disabled: preserve the original body.
struct PassthroughTextProcessor: ActionTextProcessor {
    func process(_ text: String) async throws -> ProcessedText { ProcessedText(text: text) }
}
