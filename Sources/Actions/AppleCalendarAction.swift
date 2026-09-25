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
        settingsGroup: .init(id: "storage", title: "Save", order: 0),
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
              availability: destination == nil
                  ? .needsConfiguration(message: L10n.text("action.state.select_calendar")) : .ready,
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
            processor: actionTextProcessor(preferences: preferences, id: descriptor.id, mode: .calendar), run: run)
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
        changed()
    }
    func loadDestinations() async throws -> [AppleCalendar.Destination] {
        let response = try await run(.init(requestID: UUID().uuidString, operation: "calendars"))
        guard response.status == "ok", let calendars = response.calendars, !calendars.isEmpty else {
            throw ActionFailure(localized: "error.calendar.no_calendars", code: .configuration,
                                osStatus: response.osStatus)
        }
        return calendars
    }
    func verifyAndSetDestination(_ value: AppleCalendar.Destination) async throws {
        let now = Date()
        let response = try await run(.init(requestID: UUID().uuidString, operation: "create",
            calendarID: value.id, title: "Jotway Connection Test", body: "This event can be deleted after verification.",
            start: now, end: now.addingTimeInterval(300)))
        guard response.status == "ok", response.eventID?.isEmpty == false, response.calendarID == value.id else {
            throw ActionFailure(localized: "error.calendar.verification_failed",
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

/// 存到日历（有明确时间锚点的日程写入）。
///
/// 与 `AppleRemindersAction` 同构：可自然语言点名（「加到日历 XXX」「日程：XXX」），
/// 命中即建一条 event。开始时间缺省回退当前时刻、结束缺省回退开始 + 1 小时，
/// 过境即走、本地不留记录。写入走 EventKit（复用 `AppleCalendar.run`），系统自带、无需 Apple Event。
struct AppleCalendarAction: LauncherAction {
    let descriptor: ActionDescriptor

    /// 保存位置（账号 / 日历）。为空时不可用，提示用户先在设置中选择。
    let destination: AppleCalendar.Destination?
    /// AI 处理环节：整理正文并解析 start / end。
    let processor: ActionTextProcessor
    /// 注入点：默认走真实 EventKit，测试时替换。
    let run: @MainActor @Sendable (AppleCalendar.Request) async throws -> AppleCalendar.Response
    /// 当前时间提供者：开始时间缺省时的回退基准（可注入以稳定测试）。
    let now: @Sendable () -> Date

    init(descriptor: ActionDescriptor = AppleCalendarModule.moduleDescriptor,
         destination: AppleCalendar.Destination?,
         processor: ActionTextProcessor = PassthroughTextProcessor(),
         now: @escaping @Sendable () -> Date = { Date() },
         run: @escaping @MainActor @Sendable (AppleCalendar.Request) async throws -> AppleCalendar.Response
             = { try await AppleCalendar.run($0) }) {
        self.descriptor = descriptor
        self.destination = destination
        self.processor = processor
        self.now = now
        self.run = run
    }

    func prepare(_ input: ActionInput) async throws -> PreparedAction {
        guard let destination else {
            throw ActionFailure(localized: "error.calendar.choose_destination", code: .configuration)
        }
        let processed = try await processor.process(input.text)
        let content = AppleReminders.content(fromPlainText: processed.text)
        guard !content.name.isEmpty else {
            throw ActionFailure(localized: "error.calendar.empty", code: .validation)
        }
        // AI 解析出 start/end 就用它；缺省回退当前时刻起 1 小时（end 不晚于 start 时同样回退）。
        let schedule = Self.schedule(start: processed.start, end: processed.end, now: now())
        let request = AppleCalendar.Request(
            requestID: UUID().uuidString, operation: "create",
            calendarID: destination.id, title: content.name, body: content.body,
            start: schedule.start, end: schedule.end)
        return PreparedAction(actionID: descriptor.id, inputIdentity: input.identity) {
                do {
                    let response = try await run(request)
                    guard response.status == "ok", response.eventID?.isEmpty == false else {
                        throw ActionFailure(localized: "error.calendar.create_failed", code: .processFailed,
                                            osStatus: response.osStatus)
                    }
                    return ActionOutcome(messageKey: "result.calendar.saved")
                } catch let failure as AppleCalendar.Failure {
                    throw ActionFailure(localized: "error.calendar.create_failed", code: .processFailed,
                                        osStatus: failure.osStatus)
                } catch let failure as ActionFailure {
                    throw failure
                } catch {
                    throw ActionFailure(localized: "error.calendar.create_failed_retry", code: RuntimeLog.code(error))
                }
            }
    }

    /// 开始 / 结束时间的最终取值：start 缺省回退 now，end 缺省或不晚于 start 回退 start + 1 小时。
    static func schedule(start: Date?, end: Date?, now: Date) -> (start: Date, end: Date) {
        let resolvedStart = start ?? now
        let resolvedEnd = end.flatMap { $0 > resolvedStart ? $0 : nil }
            ?? resolvedStart.addingTimeInterval(AppleCalendar.defaultDuration)
        return (resolvedStart, resolvedEnd)
    }
}
