import Foundation
import os

/// Typed, content-free totals. Late I/O cannot change an already published terminal report.
final class NotesGroupingDiagnostics: Sendable {
    enum Stage: String, Codable, Sendable { case queue, preparation, model, finalValidation, readback }
    enum Reason: String, Codable, Sendable {
        case semanticNew, noCandidates, preparationTimeout, modelTimeout, inputBudget, invalidOutput
        case configuration, providerError, readFailure, finalConflict, uncertainWrite, cancelled, stale, metadata
    }
    enum Placement: String, Codable, Sendable { case append, new, recovered, raw }
    struct Measurement: Codable, Sendable { var reads = 0; var durationMs = 0 }
    struct Report: Codable, Sendable {
        var stages: [String: Measurement] = [:]
        var candidates = 0
        var cacheHits = 0
        var cacheMisses = 0
        var cacheInvalidations = 0
        var reselected = false
        var modelDecision: Placement? = nil
        var savedAs: Placement? = nil
        var reason: Reason? = nil
        var outcome: RuntimeLog.Outcome = .failed
    }
    private struct State { var report = Report(); var finished = false }
    private let state = OSAllocatedUnfairLock(initialState: State())
    @TaskLocal static var current: NotesGroupingDiagnostics?

    func update(_ operation: @Sendable (inout Report) -> Void) {
        state.withLock { if !$0.finished { operation(&$0.report) } }
    }
    func duration(_ stage: Stage, since start: UInt64) {
        update { $0.stages[stage.rawValue, default: .init()].durationMs += RuntimeLog.milliseconds(since: start) }
    }
    /// Called only around the actual Apple Event send, not while constructing specifiers.
    func read<Value>(_ stage: Stage, operation: () throws -> Value) rethrows -> Value {
        let started = RuntimeLog.ticks()
        update { $0.stages[stage.rawValue, default: .init()].reads += 1 }
        defer { if stage == .finalValidation || stage == .readback { duration(stage, since: started) } }
        return try operation()
    }
    func finish() -> Report? {
        state.withLock {
            guard !$0.finished else { return nil }
            $0.finished = true
            return $0.report
        }
    }
}
