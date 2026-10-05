import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class AppleNotesModule: ActionModule {
    nonisolated static let moduleDescriptor = ActionDescriptor(
        id: "apple-notes", title: "Save to Notes", settingsName: "Apple Notes",
        summary: "Save notes and ideas; the fallback when no clearer intent is found.",
        titleKey: "action.notes.title", settingsNameKey: "action.notes.settings_name",
        summaryKey: "action.notes.summary", systemImageName: "note.text", tint: .orange,
        settingsGroup: .init(id: "storage", title: "Save", order: 0, titleKey: "actions.group.storage"),
        enablementPolicy: .alwaysEnabled, fallbackPriority: 0,
        intentHints: IntentHints(localKeywords: ["记一下", "存备忘录", "留个备忘", "记个备忘", "存备忘", "先存",
                                                       "save to notes", "take a note"],
            modelBinding: .capture(criteria: """
                用户想把内容留下来、记一下、稍后处理，存进系统备忘录，而不是发给他人、搜索或打开应用。
                例：记一下 明天要买牛奶；存备忘录：这段代码；留个备忘 周五交周报；先存着待会儿看。
                纯粹的报告、引用他人的话、疑问句或明确要发给某人 / 搜索 / 打开某 App 的请求不属于此 action。
                """)),
        presentationPolicy: .returnToPreviousApplication, preservesOriginalText: true)

    let descriptor = AppleNotesModule.moduleDescriptor
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    private let preferences: UserDefaults
    private let run: @MainActor @Sendable (AppleNotes.Request) async throws -> AppleNotes.Response
    private(set) var destination: AppleNotes.Destination?
    private(set) var repairFailure: ActionFailure?
    private(set) var configurationRevision = 0

    init(preferences: UserDefaults,
         run: @escaping @MainActor @Sendable (AppleNotes.Request) async throws -> AppleNotes.Response = {
             try await AppleNotes.run($0)
         }) {
        self.preferences = preferences
        self.run = run
        destination = preferences.data(forKey: "notesDestination")
            .flatMap { try? JSONDecoder().decode(AppleNotes.Destination.self, from: $0) }
    }

    var state: ActionModuleState {
        .init(configurationRevision: configurationRevision,
              availability: repairFailure.map { .needsConfiguration(message: $0.localizedDescription) }
                  ?? (destination == nil
                      ? .needsConfiguration(message: L10n.text("action.state.select_notes")) : .ready),
              summary: destination.map { L10n.text("action.state.save_to", $0.name) }
                  ?? L10n.text("action.state.no_destination"),
              hasSavedConfiguration: ["notesDestination", "notesTag", "notesAITagsEnabled",
                                      "aiRewriteEnabled.\(descriptor.id)", "aiRewritePrompt.\(descriptor.id)",
                                      "notesSupplementPrompt"]
                  .contains { preferences.object(forKey: $0) != nil })
    }

    var settings: ActionSettings? {
        ActionSettings { [unowned self] in AnyView(AppleNotesSettingsView(module: self)) }
    }

    var setup: ActionSetup? {
        let lifetime = AppleNotesSetupLifetime()
        return ActionSetup(title: L10n.text("action.notes.setup.action_title"),
                           invalidate: { lifetime.invalidate() }) { [self] onFinish in
            AnyView(AppleNotesSetupView(module: self, lifetime: lifetime, onFinish: onFinish))
        }
    }

    func refreshAvailability() {}

    func makeAction() -> any LauncherAction {
        return AppleNotesAction(descriptor: descriptor, destination: destination,
            processor: notesSupplementProcessor(preferences: preferences, id: descriptor.id),
            tag: notesTag.isEmpty ? nil : notesTag, run: { [self] request in
                try await perform(request)
            })
    }

    // Retain the existing switch, including its default, without migrating or executing old styles.
    var isAISupplementEnabled: Bool { enabledPreference("aiRewriteEnabled.\(descriptor.id)") }
    var supplementPrompt: String { preferences.string(forKey: "notesSupplementPrompt") ?? "" }
    var hasLegacyRewritePrompt: Bool {
        preferences.string(forKey: "aiRewritePrompt.\(descriptor.id)")?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
    var notesTag: String { preferences.string(forKey: "notesTag") ?? "Jotway" }
    var isAITagsEnabled: Bool { enabledPreference("notesAITagsEnabled") }

    func setDestination(_ value: AppleNotes.Destination) throws {
        let data = try JSONEncoder().encode(value)
        preferences.set(data, forKey: "notesDestination")
        guard preferences.data(forKey: "notesDestination") == data else {
            throw ActionFailure(localized: "error.destination_save_failed", code: .storage)
        }
        destination = value
        repairFailure = nil
        changed()
    }

    func loadDestinations() async throws -> [AppleNotes.Destination] {
        let expectedRevision = configurationRevision
        let response = try await perform(.init(requestID: UUID().uuidString, operation: "folders"))
        guard configurationRevision == expectedRevision else {
            throw ActionFailure(localized: "error.notes.configuration_changed", code: .stale)
        }
        guard let folders = response.folders else {
            throw ActionFailure(localized: "error.notes.folders_failed", code: .validation)
        }
        guard !folders.isEmpty else {
            let failure = ActionFailure(localized: "error.notes.no_folders", code: .configuration,
                                        osStatus: response.osStatus)
            repairFailure = failure
            changed()
            throw failure
        }
        if let destination, !folders.contains(where: { $0.id == destination.id }) {
            repairFailure = ActionFailure(localized: "error.notes.destination_missing", code: .configuration)
            changed()
        } else if repairFailure != nil {
            repairFailure = nil
            changed()
        }
        return folders
    }

    func authorizeAndSetDefaultDestination() async throws {
        let folders = try await loadDestinations()
        try Task.checkCancellation()
        // The adapter places Notes' default folder first. Keep a valid user choice.
        guard let value = folders.first(where: { $0.id == destination?.id }) ?? folders.first else {
            throw ActionFailure(localized: "error.notes.no_folders", code: .configuration)
        }
        try setDestination(value)
    }

    private func perform(_ request: AppleNotes.Request) async throws -> AppleNotes.Response {
        try Task.checkCancellation()
        let expectedRevision = configurationRevision
        do {
            let response = try await run(request)
            // A closed setup view cannot apply a late authorization response.
            try Task.checkCancellation()
            if let failure = AppleNotes.actionFailure(for: response, operation: request.operation) {
                throw failure
            }
            return response
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            let failure = AppleNotes.actionFailure(for: error, operation: request.operation)
            let missingCurrentDestination = failure.osStatus == -1728
                && request.folderID != nil && request.folderID == destination?.id
            if configurationRevision == expectedRevision,
               failure.osStatus == -1743 || missingCurrentDestination {
                repairFailure = failure
                changed()
            }
            throw failure
        }
    }

    func setAISupplementEnabled(_ enabled: Bool) { preferences.set(enabled, forKey: "aiRewriteEnabled.\(descriptor.id)"); changed() }
    func setSupplementPrompt(_ text: String) {
        let key = "notesSupplementPrompt"
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? preferences.removeObject(forKey: key) : preferences.set(text, forKey: key)
        changed()
    }
    func setNotesTag(_ raw: String) { preferences.set(cleanActionTag(raw), forKey: "notesTag"); changed() }
    func setAITagsEnabled(_ enabled: Bool) { preferences.set(enabled, forKey: "notesAITagsEnabled"); changed() }

    private func enabledPreference(_ key: String) -> Bool {
        preferences.object(forKey: key) == nil || preferences.bool(forKey: key)
    }
    private func changed() { configurationRevision &+= 1; onChange?() }
}

/// Notes always keeps the frozen original draft; the processor can only provide appended material.
struct AppleNotesAction: LauncherAction {
    let descriptor: ActionDescriptor
    let destination: AppleNotes.Destination?
    let processor: any NotesSupplementProcessor
    /// Fixed tag is appended outside the original region, together with any generated tags.
    let tag: String?
    let run: @MainActor @Sendable (AppleNotes.Request) async throws -> AppleNotes.Response

    init(descriptor: ActionDescriptor = AppleNotesModule.moduleDescriptor,
         destination: AppleNotes.Destination?,
         processor: any NotesSupplementProcessor = NoNotesSupplementProcessor(),
         tag: String? = nil,
         run: @escaping @MainActor @Sendable (AppleNotes.Request) async throws -> AppleNotes.Response
             = { try await AppleNotes.run($0) }) {
        self.descriptor = descriptor
        self.destination = destination
        self.processor = processor
        self.tag = tag
        self.run = run
    }

    func prepare(_ input: ActionInput) async throws -> PreparedAction {
        try Task.checkCancellation()
        let original = input.originalText
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ActionFailure(localized: "error.notes.empty", code: .validation)
        }
        guard let destination else {
            throw ActionFailure(localized: "error.notes.choose_destination", code: .configuration)
        }
        let supplement: NotesSupplement
        do {
            supplement = try await processor.process(original)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if RuntimeLog.code(error) == .cancelled { throw CancellationError() }
            try Task.checkCancellation()
            supplement = .empty
        }
        try Task.checkCancellation()
        let content = AppleNotes.content(fromPlainText: original, supplement: supplement,
                                         tags: tag.map { [$0] } ?? [])
        let request = AppleNotes.Request(requestID: UUID().uuidString, operation: "create",
            folderID: destination.id, noteID: nil, html: content.html)
        return PreparedAction(actionID: descriptor.id, inputIdentity: input.identity) {
            try Task.checkCancellation()
            do {
                let response = try await run(request)
                if let failure = AppleNotes.actionFailure(for: response, operation: request.operation) {
                    throw failure
                }
                guard response.noteID?.isEmpty == false else {
                    throw ActionFailure(localized: "error.notes.save_failed",
                                        code: .processFailed, osStatus: response.osStatus, executionOutcome: .unknown)
                }
                return ActionOutcome(messageKey: "result.notes.saved", effect: .created)
            } catch {
                if error is CancellationError { throw error }
                throw AppleNotes.actionFailure(for: error, operation: request.operation)
            }
        }
    }
}
