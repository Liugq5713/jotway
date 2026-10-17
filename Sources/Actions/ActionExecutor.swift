import Foundation

/// Owns one identified plan and its body preparation. Execution never rebuilds a plan.
@MainActor
final class ActionExecutor {
    struct Identity: Equatable {
        let actionID: String
        let inputIdentity: ActionInput.Identity
        let configurationIdentity: ActionConfigurationIdentity
        let panelSessionID: UUID
    }

    enum Status {
        case preparing(ActionPlan)
        case ready(ActionPlan, PreparedAction)
        case failed(ActionFailure)

        var plan: ActionPlan? {
            switch self {
            case .preparing(let plan), .ready(let plan, _): plan
            case .failed: nil
            }
        }
    }

    struct Preparation {
        let identity: Identity
        let generation: UUID
        var status: Status
    }

    var changed: ((Preparation?) -> Void)?
    private(set) var current: Preparation?
    private var building: Task<PreparedAction, Error>?
    private let compatibilitySessionID = UUID()

    isolated deinit { building?.cancel() }

    func schedule(snapshot: ActionExecutionSnapshot, input: ActionInput,
                  panelSessionID: UUID? = nil,
                  debounce: Duration = .milliseconds(500), confirmed: Bool = false) {
        let identity = Identity(actionID: snapshot.id, inputIdentity: input.identity,
            configurationIdentity: snapshot.configurationIdentity,
            panelSessionID: panelSessionID ?? compatibilitySessionID)
        if let current, current.identity == identity {
            if confirmed, snapshot.descriptor.preparationTiming == .beforeSubmission,
               case .preparing(let plan) = current.status, building == nil {
                startBuilding(plan: plan, identity: identity, generation: current.generation, debounce: .zero)
            }
            return
        }
        reset()
        let generation = UUID()
        do {
            let plan = try snapshot.action.preparation(for: input)
            guard plan.actionID == identity.actionID, plan.inputIdentity == identity.inputIdentity else {
                throw ActionFailure(localized: "action.preparation_failed", code: .validation)
            }
            if snapshot.descriptor.preparationTiming == .afterConfirmation {
                // Freeze the plan now; optional body work starts only after Session accepts
                // the submission and hides the panel. It must not depend on this executor's lifetime.
                let deferred = PreparedAction(actionID: identity.actionID, inputIdentity: identity.inputIdentity,
                                              planID: plan.id) {
                    try Task.checkCancellation()
                    let value = try await plan.build()
                    try Task.checkCancellation()
                    guard value.actionID == identity.actionID, value.inputIdentity == identity.inputIdentity,
                          value.planID == plan.id else { throw CancellationError() }
                    return try await value.execute()
                }
                current = Preparation(identity: identity, generation: generation,
                                      status: .ready(plan, deferred))
                changed?(current)
                return
            }
            current = Preparation(identity: identity, generation: generation, status: .preparing(plan))
            changed?(current)
            if snapshot.descriptor.preparationTiming != .beforeSubmission || confirmed {
                startBuilding(plan: plan, identity: identity, generation: generation,
                              debounce: snapshot.descriptor.preparationTiming == .beforeSubmission ? .zero : debounce)
            }
        } catch {
            current = Preparation(identity: identity, generation: generation,
                                  status: .failed(ActionFailure.presentation(for: error)))
            changed?(current)
        }
    }

    private func startBuilding(plan: ActionPlan, identity: Identity, generation: UUID, debounce: Duration) {
        let task = Task {
            try await Task.sleep(for: debounce)
            try Task.checkCancellation()
            let value = try await plan.build()
            try Task.checkCancellation()
            guard value.actionID == identity.actionID, value.inputIdentity == identity.inputIdentity,
                  value.planID == plan.id else { throw CancellationError() }
            return value
        }
        building = task
        Task { [weak self] in
            do {
                let value = try await task.value
                guard let self, self.current?.generation == generation,
                      self.current?.identity == identity else { return }
                self.building = nil
                self.current?.status = .ready(plan, value)
                self.changed?(self.current)
            } catch {
                guard let self, self.current?.generation == generation,
                      self.current?.identity == identity else { return }
                self.building = nil
                self.current?.status = .failed(ActionFailure.presentation(for: error))
                self.changed?(self.current)
            }
        }
    }

    func prepared(planID: UUID, snapshot: ActionExecutionSnapshot, input: ActionInput,
                  panelSessionID: UUID) -> PreparedAction? {
        guard let current, current.identity == Identity(actionID: snapshot.id, inputIdentity: input.identity,
            configurationIdentity: snapshot.configurationIdentity, panelSessionID: panelSessionID),
            case .ready(let plan, let value) = current.status,
            plan.id == planID, value.planID == planID else { return nil }
        return value
    }

    /// Only Session calls this after its confirmation gate and native editor acceptance.
    func executionTask(prepared value: PreparedAction, planID: UUID,
                       snapshot: ActionExecutionSnapshot, input: ActionInput) -> Task<ActionOutcome, Error> {
        Task {
            guard value.planID == planID, value.actionID == snapshot.id,
                  value.inputIdentity == input.identity else { throw CancellationError() }
            return try await value.execute()
        }
    }

    /// Direct callers share the identified preparation and cancellation path.
    func executionTask(snapshot: ActionExecutionSnapshot, input: ActionInput) -> Task<ActionOutcome, Error> {
        schedule(snapshot: snapshot, input: input, debounce: .zero, confirmed: true)
        guard let current, let plan = current.status.plan else {
            return Task { throw CancellationError() }
        }
        let task = building
        let cached: PreparedAction? = if case .ready(_, let value) = current.status { value } else { nil }
        return Task {
            let value: PreparedAction
            if let cached { value = cached }
            else if let task { value = try await task.value }
            else { throw CancellationError() }
            guard value.planID == plan.id, value.actionID == snapshot.id,
                  value.inputIdentity == input.identity else { throw CancellationError() }
            return try await value.execute()
        }
    }

    func reset() {
        building?.cancel()
        building = nil
        guard current != nil else { return }
        current = nil
        changed?(nil)
    }
}
