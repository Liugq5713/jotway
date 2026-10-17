import Foundation

extension NotesGroupingClassifier {
    @MainActor
    static func capability(generator: ModelTextInvocation) -> Self {
        Self { request in
            let remaining = ContinuousClock.now.duration(to: request.deadline ?? .now.advanced(by: timeout))
            guard remaining > .zero else { throw NotesGroupingDeadline.Failure.expired }
            let seconds = Double(remaining.components.seconds) + Double(remaining.components.attoseconds) / 1e18
            let output = try await generator.call(.init(instructions: request.instructions, content: request.content,
                outputFormat: .json, maximumTokens: 512, maximumTokensForThinkingModel: 16_384, maximumBytes: maximumBytes, timeout: seconds),
                loggingPurpose: .notesGrouping)
            return Response(text: output)
        }
    }
}
