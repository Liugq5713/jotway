import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class CodexModule: ActionModule {
    nonisolated static let moduleDescriptor = ActionDescriptor(
        id: "codex", title: "Run with Codex", settingsName: "Codex",
        summary: "Run your task immediately. No project needed.",
        titleKey: "action.codex.title", settingsNameKey: "action.codex.settings_name",
        summaryKey: "action.codex.summary", systemImageName: "terminal", tint: .blue,
        settingsGroup: .init(id: "conversation", title: "Conversations", order: 200,
                             titleKey: "actions.group.conversation"),
        enablementPolicy: .userToggle(defaultEnabled: true), fallbackPriority: nil,
        intentHints: IntentHints(localKeywords: []),
        presentationPolicy: .returnToPreviousApplication, preparationTiming: .beforeSubmission, applicationBundleIdentifier: "com.openai.codex")

    let descriptor = CodexModule.moduleDescriptor
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    let availability: CodexAvailability
    private let preferences: UserDefaults
    private var revision = 0
    var isAvailable: Bool { availability.state == .ready }

    init(preferences: UserDefaults = .standard, availability: CodexAvailability = .shared) {
        self.preferences = preferences; self.availability = availability
        availability.onChange = { [weak self] in
            guard let self else { return }
            self.revision &+= 1; self.onChange?()
        }
    }

    var state: ActionModuleState {
        let message = L10n.text(availability.state.messageKey)
        let value: ActionAvailability = switch availability.state {
        case .ready: .ready
        case .needsSetup: .needsConfiguration(message: message)
        case .checking, .cliMissing, .checkFailed: .unavailable(message: message)
        }
        return .init(configurationRevision: revision, availability: value,
                     summary: message, hasSavedConfiguration: false)
    }
    var settings: ActionSettings? { .init { AnyView(CodexSettingsView(module: self)) } }
    var setup: ActionSetup? {
        guard availability.state == .needsSetup else { return nil }
        return .init(title: L10n.text("action.codex.setup")) { finish in
            AnyView(CodexSetupView(module: self, finish: finish))
        }
    }
    func refreshAvailability() { availability.refreshFiles() }
    func requestAvailabilityRefresh(invalidate: Bool = false) {
        guard preferences.object(forKey: "actionEnabled.codex") == nil || preferences.bool(forKey: "actionEnabled.codex") else {
            if invalidate { availability.invalidate() }
            return
        }
        availability.requestRefresh(invalidate: invalidate)
    }
    func checkSetup() { availability.requestRefresh() }
    func makeAction() -> any LauncherAction { CodexAction(availability: availability) }

}

private struct CodexSettingsView: View {
    let module: CodexModule
    @State private var error: String?

    var body: some View {
        Form {
            Section(L10n.text("action.codex.settings_name")) {
                Text(L10n.text("action.codex.setup_help"))
                Button(L10n.text("action.codex.setup")) { openSetup() }
                Button(L10n.text("action.codex.check_setup")) { module.checkSetup() }
                Text(module.state.summary).font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
            }
            Section(L10n.text("action.codex.tasks")) {
                Text(L10n.text("action.codex.execution_help"))
                Button(L10n.text("action.codex.open_tasks")) { openTasks() }
                Text(L10n.text("action.codex.results_help")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { module.checkSetup() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            module.checkSetup()
        }
    }

    private func openSetup() {
        guard let url = Bundle.module.url(forResource: "Set Up Codex", withExtension: "command"),
              NSWorkspace.shared.open(url) else {
            error = L10n.text("action.codex.setup_failed")
            return
        }
        error = nil
    }

    private func openTasks() {
        let directory = CodexTaskRunner.tasksDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            guard NSWorkspace.shared.open(directory) else { throw CocoaError(.fileReadUnknown) }
            error = nil
        } catch {
            self.error = L10n.text("action.codex.open_tasks_failed")
        }
    }
}

private struct CodexSetupView: View {
    let module: CodexModule
    let finish: @MainActor (ActionSetupResult) -> Void

    var body: some View {
        VStack(spacing: 12) {
            CodexSettingsView(module: module)
            HStack {
                Button(L10n.text("common.cancel")) { finish(.cancelled) }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.text("action.codex.setup_done")) {
                    Task {
                        do { try await module.availability.requireReady(); finish(.completed) }
                        catch { /* The shared state already explains the failed recheck. */ }
                    }
                }
                .disabled(!module.isAvailable)
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .frame(width: 460, height: 340)
    }
}

struct CodexAction: LauncherAction {
    let descriptor = CodexModule.moduleDescriptor
    let availability: CodexAvailability

    func prepare(_ input: ActionInput) async throws -> PreparedAction {
        let prompt = input.text
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ActionFailure(localized: "action.codex.empty", code: .validation)
        }
        try await availability.requireReady()
        return PreparedAction(actionID: descriptor.id, inputIdentity: input.identity) {
            let result = try await CodexTaskRunner.shared.run(prompt: prompt, availability: availability)
            return ActionOutcome(messageKey: "action.codex.completed", effect: .completed,
                                 showsCompletionNotice: true,
                                 completionDestination: .url(result.conversationURL, fallback: result.output))
        }
    }

}
