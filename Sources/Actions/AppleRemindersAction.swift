import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class AppleRemindersModule: ActionModule {
    nonisolated static let moduleDescriptor = ActionDescriptor(
        id: "apple-reminders", title: "Save to Reminders", settingsName: "Apple Reminders",
        summary: "Create reminders and extract due dates from text.",
        titleKey: "action.reminders.title", settingsNameKey: "action.reminders.settings_name",
        summaryKey: "action.reminders.summary", systemImageName: "checklist", tint: .teal,
        settingsGroup: .init(id: "storage", title: "Save", order: 0, titleKey: "actions.group.storage"),
        enablementPolicy: .alwaysEnabled, fallbackPriority: 100,
        intentHints: IntentHints(localKeywords: ["提醒我", "待办", "别忘了", "记得", "todo", "to-do", "to do",
                                                       "remind me", "add a reminder"],
            modelBinding: .capture(criteria: """
                用户想记下一件要去做的事、别忘了、稍后要执行或需要被提醒，存进系统提醒事项作为待办，
                而不是登记到日历、单纯记录一段内容、发给他人、搜索或打开应用。
                例：提醒我 明天交周报；待办：给张三回邮件；别忘了 续费域名；记得 买牛奶。
                有明确日期时间锚点的会议 / 约会 / 日程属于日历 action；纯粹的资料备忘不属于此 action。
                """)),
        presentationPolicy: .returnToPreviousApplication)

    let descriptor = AppleRemindersModule.moduleDescriptor
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    private let preferences: UserDefaults
    private let run: @MainActor @Sendable (AppleReminders.Request) async throws -> AppleReminders.Response
    private(set) var destination: AppleReminders.Destination?
    private(set) var configurationRevision = 0

    init(preferences: UserDefaults,
         run: @escaping @MainActor @Sendable (AppleReminders.Request) async throws -> AppleReminders.Response = {
             try await AppleReminders.run($0)
         }) {
        self.preferences = preferences
        self.run = run
        destination = preferences.data(forKey: "remindersDestination")
            .flatMap { try? JSONDecoder().decode(AppleReminders.Destination.self, from: $0) }
    }

    var state: ActionModuleState {
        .init(configurationRevision: configurationRevision,
              availability: destination == nil
                  ? .needsConfiguration(message: L10n.text("action.state.select_reminders")) : .ready,
              summary: destination.map { L10n.text("action.state.save_to", $0.name) }
                  ?? L10n.text("action.state.no_destination"),
              hasSavedConfiguration: ["remindersDestination", "aiRewriteEnabled.\(descriptor.id)",
                                      "aiRewritePrompt.\(descriptor.id)"]
                  .contains { preferences.object(forKey: $0) != nil })
    }
    var settings: ActionSettings? {
        ActionSettings { [unowned self] in AnyView(AppleRemindersSettingsView(module: self)) }
    }
    func refreshAvailability() {}
    func makeAction() -> any LauncherAction {
        AppleRemindersAction(descriptor: descriptor, destination: destination,
            processor: actionTextProcessor(preferences: preferences, id: descriptor.id, mode: .reminders), run: run)
    }

    var isAIRewriteEnabled: Bool { enabledPreference("aiRewriteEnabled.\(descriptor.id)") }
    var rewritePrompt: String { preferences.string(forKey: "aiRewritePrompt.\(descriptor.id)") ?? "" }
    func setDestination(_ value: AppleReminders.Destination) throws {
        let data = try JSONEncoder().encode(value)
        preferences.set(data, forKey: "remindersDestination")
        guard preferences.data(forKey: "remindersDestination") == data else {
            throw ActionFailure(localized: "error.destination_save_failed", code: .storage)
        }
        destination = value
        changed()
    }
    func loadDestinations() async throws -> [AppleReminders.Destination] {
        let response = try await run(.init(requestID: UUID().uuidString, operation: "lists"))
        guard response.status == "ok", let lists = response.lists, !lists.isEmpty else {
            throw ActionFailure(localized: "error.reminders.no_lists", code: .configuration,
                                osStatus: response.osStatus)
        }
        return lists
    }
    func verifyAndSetDestination(_ value: AppleReminders.Destination) async throws {
        let response = try await run(.init(requestID: UUID().uuidString, operation: "create",
            listID: value.id, name: "Jotway Connection Test", body: "This item can be deleted after verification.", due: .none))
        guard response.status == "ok", response.reminderID?.isEmpty == false, response.listID == value.id else {
            throw ActionFailure(localized: "error.reminders.verification_failed",
                                code: .validation, osStatus: response.osStatus)
        }
        try setDestination(value)
    }
    func setAIRewriteEnabled(_ enabled: Bool) { preferences.set(enabled, forKey: "aiRewriteEnabled.\(descriptor.id)"); changed() }
    func setRewritePrompt(_ text: String) {
        let key = "aiRewritePrompt.\(descriptor.id)"
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? preferences.removeObject(forKey: key) : preferences.set(text, forKey: key)
        changed()
    }
    private func enabledPreference(_ key: String) -> Bool {
        preferences.object(forKey: key) == nil || preferences.bool(forKey: key)
    }
    private func changed() { configurationRevision &+= 1; onChange?() }
}

/// The destination and locally resolved time are frozen before body preparation.
struct AppleRemindersAction: LauncherAction {
    let descriptor: ActionDescriptor
    let destination: AppleReminders.Destination?
    let processor: ActionTextProcessor
    let run: @MainActor @Sendable (AppleReminders.Request) async throws -> AppleReminders.Response

    init(descriptor: ActionDescriptor = AppleRemindersModule.moduleDescriptor,
         destination: AppleReminders.Destination?,
         processor: ActionTextProcessor = PassthroughTextProcessor(),
         run: @escaping @MainActor @Sendable (AppleReminders.Request) async throws -> AppleReminders.Response
             = { try await AppleReminders.run($0) }) {
        self.descriptor = descriptor
        self.destination = destination
        self.processor = processor
        self.run = run
    }

    func preparation(for input: ActionInput, context: ScheduleContext) throws -> ActionPreparation {
        guard let destination else {
            throw ActionFailure(localized: "error.reminders.choose_destination", code: .configuration)
        }
        guard !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ActionFailure(localized: "error.reminders.empty", code: .validation)
        }
        let resolution = ScheduleResolver.resolve(input.text, context: context)
        let due: ReminderDue
        switch resolution.reminderDue {
        case .failure(let issue): return .needsInput(issue.inContext(context))
        case .success(let value): due = value
        }
        let source: ScheduleSource?
        if case .resolved(let parsed) = resolution { source = parsed.source } else { source = nil }
        let planID = UUID()
        return .ready(ActionPlan(id: planID, actionID: descriptor.id, inputIdentity: input.identity,
            summary: .reminder(targetID: destination.id, targetName: destination.name, due: due, source: source),
            context: context, timeResolution: resolution) {
                try Task.checkCancellation()
                let processed = try await processor.process(input.text)
                try Task.checkCancellation()
                guard !processed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ActionFailure(localized: "error.reminders.empty", code: .validation)
                }
                let content = AppleReminders.content(fromPlainText: processed.text)
                let request = AppleReminders.Request(requestID: UUID().uuidString, operation: "create",
                    listID: destination.id, name: content.name, body: content.body, due: due)
                return PreparedAction(actionID: descriptor.id, inputIdentity: input.identity, planID: planID) {
                    do {
                        let response = try await run(request)
                        guard response.status == "ok", response.reminderID?.isEmpty == false else {
                            throw ActionFailure(localized: "error.reminders.create_failed", code: .processFailed,
                                                osStatus: response.osStatus, executionOutcome: .unknown)
                        }
                        return ActionOutcome(messageKey: "result.reminders.saved", effect: .created)
                    } catch let failure as AppleReminders.Failure {
                        throw AppleReminders.actionFailure(for: failure, operation: "create")
                    } catch let failure as ActionFailure {
                        throw failure
                    } catch {
                        if error is CancellationError { throw error }
                        throw ActionFailure(localized: "error.reminders.create_failed_retry", code: RuntimeLog.code(error))
                    }
                }
            })
    }
}
