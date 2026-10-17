import AppKit
import Foundation

@MainActor
struct BundledActionDependencies {
    var makeNotes: (@MainActor (UserDefaults) -> AppleNotesModule)? = nil
    var notesRun: @MainActor @Sendable (AppleNotes.Request) async throws -> AppleNotes.Response = {
        try await AppleNotes.run($0)
    }
}

@MainActor
enum BundledActions {
    static func modules(preferences: UserDefaults, models suppliedModels: ModelConfiguration? = nil,
                        clipboard: ClipboardHistory? = nil,
                        dependencies: BundledActionDependencies = .init()) -> [any ActionModule] {
        let models = suppliedModels ?? ModelConfiguration(preferences: preferences)
        let notes = dependencies.makeNotes?(preferences)
            ?? AppleNotesModule(preferences: preferences, models: models, run: dependencies.notesRun)
        return [
            notes,
            CodexModule(preferences: preferences),
            ClipboardModule(history: clipboard ?? ClipboardHistory(preferences: preferences)),
        ]
    }
}

@MainActor
func notesSupplementProcessor(preferences: UserDefaults, frozen: ModelTextInvocation, id: String, retriever: NotesRetriever? = nil,
                              historyUnavailable: NotesSupplementResult.Retrieval = .unavailable,
                              retrievalQuery: String? = nil, excludedNoteID: String? = nil,
                              validate: @escaping @Sendable () async throws -> Void = { try Task.checkCancellation() }) -> any NotesSupplementProcessor {
    let enabledKey = "aiRewriteEnabled.\(id)"
    let enabled = preferences.object(forKey: enabledKey) == nil || preferences.bool(forKey: enabledKey)
    guard enabled else { return NoNotesSupplementProcessor() }
    let provider = frozen.validating(validate)
    return AINotesSupplementProcessor(provider: provider,
        preferenceOverride: preferences.string(forKey: "notesSupplementPrompt"),
        retriever: retriever, historyUnavailable: historyUnavailable,
        retrievalQuery: retrievalQuery, excludedNoteID: excludedNoteID, validate: validate)
}

func cleanActionTag(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while value.hasPrefix("#") { value.removeFirst() }
    return value.components(separatedBy: .whitespacesAndNewlines).joined()
}
