import Foundation

/// action 准备、取消、缓存与执行的唯一 seam。
@MainActor
final class ActionExecutor {
    private struct Key: Equatable {
        let actionID: String
        let inputIdentity: ActionInput.Identity
        let configurationIdentity: ActionConfigurationIdentity
    }

    private var prepared: (key: Key, value: PreparedAction)?
    private var preparing: (key: Key, generation: UUID, task: Task<PreparedAction, Error>)?

    func schedule(snapshot: ActionExecutionSnapshot, input: ActionInput, debounce: Duration = .milliseconds(500)) {
        let action = snapshot.action
        let key = Key(actionID: snapshot.id, inputIdentity: input.identity,
                      configurationIdentity: snapshot.configurationIdentity)
        if prepared?.key == key || preparing?.key == key { return }
        preparing?.task.cancel()
        prepared = nil
        let generation = UUID()
        let task = Task {
            try await Task.sleep(for: debounce)
            try Task.checkCancellation()
            return try await action.prepare(input)
        }
        preparing = (key, generation, task)
        Task { [weak self] in
            guard let self else { return }
            do {
                let value = try await task.value
                guard !Task.isCancelled, self.preparing?.key == key,
                      self.preparing?.generation == generation else { return }
                self.prepared = (key, value)
                self.preparing = nil
            } catch {
                if self.preparing?.key == key, self.preparing?.generation == generation { self.preparing = nil }
            }
        }
    }

    func executionTask(snapshot: ActionExecutionSnapshot, input: ActionInput) -> Task<ActionOutcome, Error> {
        let action = snapshot.action
        let key = Key(actionID: snapshot.id, inputIdentity: input.identity,
                      configurationIdentity: snapshot.configurationIdentity)
        let preparation: Task<PreparedAction, Error>
        if let cached = prepared, cached.key == key {
            preparation = Task { cached.value }
        } else if let active = preparing, active.key == key {
            preparation = active.task
            preparing = nil
        } else {
            preparing?.task.cancel()
            preparation = Task { try await action.prepare(input) }
        }
        prepared = nil
        return Task {
            let value = try await preparation.value
            guard value.actionID == key.actionID, value.inputIdentity == key.inputIdentity else {
                throw CancellationError()
            }
            return try await value.execute()
        }
    }

    func reset() {
        preparing?.task.cancel()
        preparing = nil
        prepared = nil
    }
}
