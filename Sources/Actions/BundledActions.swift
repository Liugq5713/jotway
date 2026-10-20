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

func cleanActionTag(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while value.hasPrefix("#") { value.removeFirst() }
    return value.components(separatedBy: .whitespacesAndNewlines).joined()
}
