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
        case needsInput(TimeInputIssue)
        case preparing(ActionPlan)
        case ready(ActionPlan, PreparedAction)
        case failed(ActionFailure)

        var plan: ActionPlan? {
            switch self {
            case .preparing(let plan), .ready(let plan, _): plan
            case .needsInput, .failed: nil
            }
        }
    }

    struct Preparation {
        let identity: Identity
        let generation: UUID
        let context: ScheduleContext
        var status: Status
    }

    var changed: ((Preparation?) -> Void)?
    private(set) var current: Preparation?
    private var building: Task<PreparedAction, Error>?
    private let compatibilitySessionID = UUID()

    isolated deinit { building?.cancel() }

    func schedule(snapshot: ActionExecutionSnapshot, input: ActionInput,
                  context: ScheduleContext? = nil, panelSessionID: UUID? = nil,
                  debounce: Duration = .milliseconds(500)) {
        let identity = Identity(actionID: snapshot.id, inputIdentity: input.identity,
            configurationIdentity: snapshot.configurationIdentity,
            panelSessionID: panelSessionID ?? compatibilitySessionID)
        if current?.identity == identity { return }
        reset()
        let context = context ?? ScheduleContext(referenceDate: Date(), timeZone: .current)
        let generation = UUID()
        do {
            switch try snapshot.action.preparation(for: input, context: context) {
            case .needsInput(let issue):
                current = Preparation(identity: identity, generation: generation, context: context, status: .needsInput(issue))
                changed?(current)
            case .ready(let plan):
                guard plan.actionID == identity.actionID, plan.inputIdentity == identity.inputIdentity,
                      plan.context == context, plan.hasConsistentSummary else {
                    throw ActionFailure(localized: "schedule.issue.preparation_failed", code: .validation)
                }
                current = Preparation(identity: identity, generation: generation, context: context, status: .preparing(plan))
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
                changed?(current)
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
        } catch {
            current = Preparation(identity: identity, generation: generation, context: context,
                                  status: .failed(ActionFailure.presentation(for: error)))
            changed?(current)
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

    /// Retained for callers exercising summary-free actions directly; never bypasses a time summary.
    func executionTask(snapshot: ActionExecutionSnapshot, input: ActionInput) -> Task<ActionOutcome, Error> {
        schedule(snapshot: snapshot, input: input, debounce: .zero)
        guard let current, let plan = current.status.plan, plan.summary == nil else {
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
