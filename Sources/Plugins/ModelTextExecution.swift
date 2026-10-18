import Foundation

extension ModelTextInvocation {
    /// One frozen model, one attempt, and one deadline including the provider's queue.
    static func bounded(_ invocation: Self, capability: ModelConfiguration.Capability,
                        validate: @escaping @Sendable () async throws -> Void) -> Self {
        var result = Self(version: invocation.version, modelID: { invocation.modelID }, generateWithEvents: { request, partial, event in
            let budget = min(request.timeout, capability == .fast ? 120 : 300)
            guard budget > 0 else { throw ModelDeadline.expired }
            let deadline = ContinuousClock.now.advanced(by: .seconds(budget))
            var input = request
            input.timeout = budget
            if capability == .deep { input.streaming = true }
            let frozen = input
            return try await ModelDeadline.run(until: deadline) {
                try Task.checkCancellation()
                try await validate()
                try await ModelValidation.current?()
                let output = try await invocation.call(frozen, onEvent: event, onPartial: partial)
                try Task.checkCancellation()
                try await validate()
                try await ModelValidation.current?()
                return output
            }
        })
        result.capability = capability
        result.providerID = invocation.providerID
        result.expectedModelID = invocation.expectedModelID
        result.requestTimeout = capability == .fast ? 120 : 300
        return result
    }
}
