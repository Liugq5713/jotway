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
        settingsGroup: .init(id: "storage", title: "Save", order: 0),
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
            listID: value.id, name: "Jotway Connection Test", body: "This item can be deleted after verification.", due: nil))
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

/// 存到提醒事项（待办版的默认写入）。
///
/// 与 `AppleNotesAction` 同构：可自然语言点名（「提醒我 XXX」「待办：XXX」），
/// 命中即建一条 reminder。到期时间默认取当前时刻，过境即走、本地不留记录。
/// 写入走 EventKit（复用 `AppleReminders.run`），系统自带、无需 Apple Event。
struct AppleRemindersAction: LauncherAction {
    let descriptor: ActionDescriptor

    /// 保存位置（账号 / 列表）。为空时不可用，提示用户先在设置中选择。
    let destination: AppleReminders.Destination?
    /// AI 处理环节；第一版 pass-through。
    let processor: ActionTextProcessor
    /// 注入点：默认走真实 EventKit，测试时替换。
    let run: @MainActor @Sendable (AppleReminders.Request) async throws -> AppleReminders.Response
    /// 到期时间提供者：默认取当前时刻（可注入以稳定测试 / 未来接时间解析）。
    let dueDate: @Sendable () -> Date?

    init(descriptor: ActionDescriptor = AppleRemindersModule.moduleDescriptor,
         destination: AppleReminders.Destination?,
         processor: ActionTextProcessor = PassthroughTextProcessor(),
         dueDate: @escaping @Sendable () -> Date? = { Date() },
         run: @escaping @MainActor @Sendable (AppleReminders.Request) async throws -> AppleReminders.Response
             = { try await AppleReminders.run($0) }) {
        self.descriptor = descriptor
        self.destination = destination
        self.processor = processor
        self.dueDate = dueDate
        self.run = run
    }

    func prepare(_ input: ActionInput) async throws -> PreparedAction {
        guard let destination else {
            throw ActionFailure(localized: "error.reminders.choose_destination", code: .configuration)
        }
        let processed = try await processor.process(input.text)
        let content = AppleReminders.content(fromPlainText: processed.text)
        guard !content.name.isEmpty else {
            throw ActionFailure(localized: "error.reminders.empty", code: .validation)
        }
        let request = AppleReminders.Request(
            requestID: UUID().uuidString, operation: "create",
            listID: destination.id, name: content.name, body: content.body,
            due: processed.due ?? dueDate())
        return PreparedAction(actionID: descriptor.id, inputIdentity: input.identity) {
            do {
                let response = try await run(request)
                guard response.status == "ok", response.reminderID?.isEmpty == false else {
                    throw ActionFailure(localized: "error.reminders.create_failed", code: .processFailed,
                                        osStatus: response.osStatus)
                }
                return ActionOutcome(messageKey: "result.reminders.saved")
            } catch let failure as AppleReminders.Failure {
                throw ActionFailure(localized: "error.reminders.create_failed", code: .processFailed,
                                    osStatus: failure.osStatus)
            } catch let failure as ActionFailure {
                throw failure
            } catch {
                throw ActionFailure(localized: "error.reminders.create_failed_retry", code: RuntimeLog.code(error))
            }
        }
    }
}
