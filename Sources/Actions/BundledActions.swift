import AppKit
import Foundation

@MainActor
struct BundledActionDependencies {
    var notesRun: @MainActor @Sendable (AppleNotes.Request) async throws -> AppleNotes.Response = {
        try await AppleNotes.run($0)
    }
    var remindersRun: @MainActor @Sendable (AppleReminders.Request) async throws -> AppleReminders.Response = {
        try await AppleReminders.run($0)
    }
    var calendarRun: @MainActor @Sendable (AppleCalendar.Request) async throws -> AppleCalendar.Response = {
        try await AppleCalendar.run($0)
    }
    var chromeLocate: @MainActor @Sendable () -> URL? = {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome")
    }
    var chromeOpen: ChromeConnector.Open = { url, application, configuration in
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration)
    }
}

@MainActor
enum BundledActions {
    static func modules(preferences: UserDefaults,
                        dependencies: BundledActionDependencies = .init()) -> [any ActionModule] {
        [
            AppleNotesModule(preferences: preferences, run: dependencies.notesRun),
            AppleRemindersModule(preferences: preferences, run: dependencies.remindersRun),
            AppleCalendarModule(preferences: preferences, run: dependencies.calendarRun),
            ChromeModule(locate: dependencies.chromeLocate, open: dependencies.chromeOpen),
            ChatGPTModule(),
        ]
    }
}

func actionTextProcessor(preferences: UserDefaults, id: String, mode: AITextProcessor.Mode,
                         notesAutoTags: Bool = false) -> any ActionTextProcessor {
    let enabledKey = "aiRewriteEnabled.\(id)"
    let enabled = preferences.object(forKey: enabledKey) == nil || preferences.bool(forKey: enabledKey)
    guard enabled else { return PassthroughTextProcessor() }
    let deepSeek = DeepSeek.source()
    let provider = AIProviderPlugin(configuration: { try deepSeek.configure(nil) })
    let override = preferences.string(forKey: "aiRewritePrompt.\(id)")
    return AITextProcessor(provider: provider, mode: mode,
                           styleOverride: override?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                               ? override : nil,
                           notesAutoTags: notesAutoTags)
}

func cleanActionTag(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while value.hasPrefix("#") { value.removeFirst() }
    return value.components(separatedBy: .whitespacesAndNewlines).joined()
}
