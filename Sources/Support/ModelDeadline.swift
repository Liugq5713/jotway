import Foundation
import os

/// Resolve once without joining cancelled work that may ignore cancellation.
enum ModelDeadline {
    static func seconds(until deadline: ContinuousClock.Instant) -> TimeInterval {
        let value = ContinuousClock.now.duration(to: deadline).components
        return max(0, Double(value.seconds) + Double(value.attoseconds) / 1e18)
    }
    static var expired: AIProviderPlugin.Failure {
        .init(message: "The model request timed out", runtimeLogCode: .timeout)
    }
    static func run<Value: Sendable>(until deadline: ContinuousClock.Instant,
                                    work: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw expired }
        let completion = Completion<Value>()
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard completion.install(continuation) else { return }
                let worker = Task {
                    do {
                        let result = try await work()
                        try Task.checkCancellation()
                        guard ContinuousClock.now < deadline else { throw expired }
                        completion.resolve(.success(result))
                    } catch { completion.resolve(.failure(error)) }
                }
                let timer = Task {
                    do { try await Task.sleep(until: deadline, clock: .continuous) }
                    catch { return }
                    completion.resolve(.failure(expired))
                }
                completion.install(tasks: [worker, timer])
            }
        } onCancel: { completion.resolve(.failure(CancellationError())) }
        try Task.checkCancellation()
        return result
    }
    private final class Completion<Value: Sendable>: Sendable {
        private struct State {
            var completed = false
            var early: Result<Value, Error>?
            var continuation: CheckedContinuation<Value, Error>?
            var tasks: [Task<Void, Never>] = []
        }
        private let state = OSAllocatedUnfairLock(initialState: State())
        func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
            let early = state.withLock { value in
                if value.completed { let result = value.early; value.early = nil; return result }
                value.continuation = continuation; return nil
            }
            if let early { continuation.resume(with: early); return false }
            return true
        }
        func install(tasks: [Task<Void, Never>]) {
            let completed = state.withLock { value in
                if value.completed { return true }
                value.tasks = tasks; return false
            }
            if completed { tasks.forEach { $0.cancel() } }
        }
        func resolve(_ result: Result<Value, Error>) {
            let (continuation, tasks) = state.withLock { value -> (CheckedContinuation<Value, Error>?, [Task<Void, Never>]) in
                guard !value.completed else { return (nil, []) }
                value.completed = true
                let continuation = value.continuation
                if continuation == nil { value.early = result }
                value.continuation = nil
                let tasks = value.tasks; value.tasks = []
                return (continuation, tasks)
            }
            continuation?.resume(with: result)
            tasks.forEach { $0.cancel() }
        }
    }
}
