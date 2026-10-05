import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class AppleCalendarModule: ActionModule {
    nonisolated static let moduleDescriptor = ActionDescriptor(
        id: "apple-calendar", title: "Save to Calendar", settingsName: "Apple Calendar",
        summary: "Create events; events without an end time last one hour.",
        titleKey: "action.calendar.title", settingsNameKey: "action.calendar.settings_name",
        summaryKey: "action.calendar.summary", systemImageName: "calendar", tint: .red,
        settingsGroup: .init(id: "storage", title: "Save", order: 0, titleKey: "actions.group.storage"),
        enablementPolicy: .alwaysEnabled, fallbackPriority: 200,
        intentHints: IntentHints(localKeywords: ["加到日历", "记到日历", "排个日程", "约个会", "日程：", "日程:",
                                                       "add to calendar", "schedule a meeting"],
            modelBinding: .capture(criteria: """
                用户想把一场有明确日期或时间锚点的活动、会议、约会登记到系统日历成为日程，
                而不是设置待办提醒、单纯记录一段内容、发给他人、搜索或打开应用。
                例：明天下午三点和老王开会；周五下午两点产品评审；下周三晚上看电影。
                没有固定时间的待办、纯粹的资料备忘不属于此 action。
                """)),
        presentationPolicy: .returnToPreviousApplication)

    let descriptor = AppleCalendarModule.moduleDescriptor
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    private let preferences: UserDefaults
    private let run: @MainActor @Sendable (AppleCalendar.Request) async throws -> AppleCalendar.Response
    private(set) var destination: AppleCalendar.Destination?
    private(set) var repairFailure: ActionFailure?
    private(set) var configurationRevision = 0

    init(preferences: UserDefaults,
         run: @escaping @MainActor @Sendable (AppleCalendar.Request) async throws -> AppleCalendar.Response = {
             try await AppleCalendar.run($0)
         }) {
        self.preferences = preferences
        self.run = run
        destination = preferences.data(forKey: "calendarDestination")
            .flatMap { try? JSONDecoder().decode(AppleCalendar.Destination.self, from: $0) }
    }

    var state: ActionModuleState {
        .init(configurationRevision: configurationRevision,
              availability: repairFailure.map { .needsConfiguration(message: $0.localizedDescription) }
                  ?? (destination == nil
                      ? .needsConfiguration(message: L10n.text("action.state.select_calendar")) : .ready),
              summary: destination.map { L10n.text("action.state.save_to", $0.name) }
                  ?? L10n.text("action.state.no_destination"),
              hasSavedConfiguration: ["calendarDestination", "aiRewriteEnabled.\(descriptor.id)",
                                      "aiRewritePrompt.\(descriptor.id)"]
                  .contains { preferences.object(forKey: $0) != nil })
    }
    var settings: ActionSettings? {
        ActionSettings { [unowned self] in AnyView(AppleCalendarSettingsView(module: self)) }
    }
    func refreshAvailability() {}
    func makeAction() -> any LauncherAction {
        AppleCalendarAction(descriptor: descriptor, destination: destination,
            processor: actionTextProcessor(preferences: preferences, id: descriptor.id, mode: .calendar),
            run: { [self] request in try await perform(request) })
    }

    var isAIRewriteEnabled: Bool { enabledPreference("aiRewriteEnabled.\(descriptor.id)") }
    var rewritePrompt: String { preferences.string(forKey: "aiRewritePrompt.\(descriptor.id)") ?? "" }
    func setDestination(_ value: AppleCalendar.Destination) throws {
        let data = try JSONEncoder().encode(value)
        preferences.set(data, forKey: "calendarDestination")
        guard preferences.data(forKey: "calendarDestination") == data else {
            throw ActionFailure(localized: "error.destination_save_failed", code: .storage)
        }
        destination = value
        repairFailure = nil
        changed()
    }
    func loadDestinations() async throws -> [AppleCalendar.Destination] {
        let values = try await readDestinations(allowAuthorizationPrompt: false)
        if let destination, !values.contains(where: { $0.id == destination.id }) {
            repairFailure = ActionFailure(localized: "destination.changed", code: .configuration)
            changed()
        } else if repairFailure != nil {
            repairFailure = nil
            changed()
        }
        return values
    }

    func authorizeAndSetDefaultDestination() async throws {
        let values = try await readDestinations(allowAuthorizationPrompt: true)
        let preferred = values.first { $0.id == destination?.id } ?? values[0]
        try setDestination(preferred)
    }

    private func readDestinations(allowAuthorizationPrompt: Bool) async throws -> [AppleCalendar.Destination] {
        let expectedRevision = configurationRevision
        let response = try await perform(.init(requestID: UUID().uuidString, operation: "calendars",
                                               allowAuthorizationPrompt: allowAuthorizationPrompt))
        try Task.checkCancellation()
        guard configurationRevision == expectedRevision else { throw CancellationError() }
        guard let values = response.calendars, !values.isEmpty else {
            let failure = ActionFailure(localized: "error.calendar.no_calendars", code: .configuration,
                                        osStatus: response.osStatus)
            repairFailure = failure
            changed()
            throw failure
        }
        return values
    }

    private func perform(_ request: AppleCalendar.Request) async throws -> AppleCalendar.Response {
        try Task.checkCancellation()
        let expectedRevision = configurationRevision
        do {
            let response = try await run(request)
            try Task.checkCancellation()
            guard response.status == "ok" else {
                throw ActionFailure(localized: request.operation == "calendars"
                    ? "error.calendar.no_calendars" : "error.calendar.create_failed",
                    code: request.operation == "calendars" ? .configuration : .processFailed,
                    osStatus: response.osStatus)
            }
            return response
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            let failure = AppleCalendar.actionFailure(for: error, operation: request.operation)
            let isObsoleteDestination = (error as? AppleCalendar.Failure)?.kind == .destination
                && request.calendarID != destination?.id
            if configurationRevision == expectedRevision, failure.code == .configuration, !isObsoleteDestination {
                repairFailure = failure
                changed()
            }
            throw failure
        }
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

/// A local schedule and destination are frozen before any optional body rewriting.
struct AppleCalendarAction: LauncherAction {
    let descriptor: ActionDescriptor
    let destination: AppleCalendar.Destination?
    let processor: ActionTextProcessor
    let run: @MainActor @Sendable (AppleCalendar.Request) async throws -> AppleCalendar.Response

    init(descriptor: ActionDescriptor = AppleCalendarModule.moduleDescriptor,
         destination: AppleCalendar.Destination?,
         processor: ActionTextProcessor = PassthroughTextProcessor(),
         run: @escaping @MainActor @Sendable (AppleCalendar.Request) async throws -> AppleCalendar.Response
             = { try await AppleCalendar.run($0) }) {
        self.descriptor = descriptor
        self.destination = destination
        self.processor = processor
        self.run = run
    }

    func preparation(for input: ActionInput, context: ScheduleContext) throws -> ActionPreparation {
        guard let destination else {
            throw ActionFailure(localized: "error.calendar.choose_destination", code: .configuration)
        }
        guard !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ActionFailure(localized: "error.calendar.empty", code: .validation)
        }
        let resolution = ScheduleResolver.resolve(input.text, context: context)
        let schedule: CalendarSchedule
        switch resolution.calendarSchedule {
        case .failure(let issue): return .needsInput(issue.inContext(context))
        case .success(let value): schedule = value
        }
        guard case .resolved(let parsed) = resolution else {
            throw ActionFailure(localized: "error.calendar.invalid_schedule", code: .validation)
        }
        let planID = UUID()
        return .ready(ActionPlan(id: planID, actionID: descriptor.id, inputIdentity: input.identity,
            summary: .calendar(targetID: destination.id, targetName: destination.name,
                               schedule: schedule, source: parsed.source),
            context: context, timeResolution: resolution) {
                try Task.checkCancellation()
                let processed = try await processor.process(input.text)
                try Task.checkCancellation()
                guard !processed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ActionFailure(localized: "error.calendar.empty", code: .validation)
                }
                let content = AppleReminders.content(fromPlainText: processed.text)
                let request = AppleCalendar.Request(requestID: UUID().uuidString, operation: "create",
                    calendarID: destination.id, title: content.name, body: content.body, schedule: schedule)
                return PreparedAction(actionID: descriptor.id, inputIdentity: input.identity, planID: planID) {
                    do {
                        let response = try await run(request)
                        guard response.status == "ok", response.eventID?.isEmpty == false else {
                            throw ActionFailure(localized: "error.calendar.create_failed", code: .processFailed,
                                                osStatus: response.osStatus, executionOutcome: .unknown)
                        }
                        return ActionOutcome(messageKey: "result.calendar.saved", effect: .created)
                    } catch let failure as AppleCalendar.Failure {
                        throw AppleCalendar.actionFailure(for: failure, operation: "create")
                    } catch let failure as ActionFailure {
                        throw failure
                    } catch {
                        if error is CancellationError { throw error }
                        throw ActionFailure(localized: "error.calendar.create_failed_retry", code: RuntimeLog.code(error))
                    }
                }
            })
    }
}
