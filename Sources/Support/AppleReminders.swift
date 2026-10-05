import EventKit
import Foundation

/// 通过 EventKit 直接读写系统提醒事项数据库——不经 Apple Events，目标 App 无需运行。
///
/// 走"提醒事项数据访问"权限（`requestFullAccessToReminders`，TCC 独立于 Automation），
/// 沙盒需 `com.apple.security.personal-information.calendars` + Info.plist 的
/// `NSRemindersFullAccessUsageDescription`。对外接口与旧 Apple Event 版保持一致，上层无感。
enum AppleReminders {
    struct Destination: Codable, Equatable, Sendable, Identifiable {
        let id: String
        let name: String
    }

    struct Request: Sendable {
        let requestID: String
        /// "lists"（读账号/列表）或 "create"（建提醒）。
        let operation: String
        var listID: String?
        /// 提醒标题（reminder title）。
        var name: String?
        /// 提醒备注（reminder notes）；为空则不写。
        var body: String?
        /// No date, floating Gregorian date, or an instant in the plan's frozen time zone.
        var due: ReminderDue = .none
        /// Only an explicit authorization button may request the system permission prompt.
        var allowAuthorizationPrompt = false
    }

    struct Response: Sendable {
        var version: Int
        var requestID: String?
        var status: String
        var lists: [Destination]?
        var reminderID: String?
        var listID: String?
        var message: String?
        /// 失败时的底层错误码（EventKit / EKError），用于诊断日志。
        var osStatus: Int?
    }

    struct Failure: LocalizedError {
        enum Kind: Sendable { case operation, permission, destination, validation }
        let message: String
        /// 仅能证明写入根本未开始的错误可直接重试。
        var notStarted = false
        /// 失败时的底层错误码，用于诊断日志。
        var osStatus: Int? = nil
        var kind: Kind = .operation
        var errorDescription: String? { message }
    }

    static func actionFailure(for error: Error, operation: String) -> ActionFailure {
        if let failure = error as? ActionFailure { return failure }
        let failure = error as? Failure
        switch failure?.kind {
        case .validation:
            return ActionFailure(localized: "error.reminders.invalid_due", code: .validation,
                                 osStatus: failure?.osStatus, executionOutcome: .failed)
        case .permission:
            return ActionFailure(localized: "reminders.permission_denied", code: .configuration,
                                 osStatus: failure?.osStatus)
        case .destination:
            return ActionFailure(localized: "destination.changed", code: .configuration,
                                 osStatus: failure?.osStatus)
        default:
            return ActionFailure(localized: operation == "lists"
                ? "error.reminders.no_lists" : "error.reminders.create_failed",
                code: .processFailed, osStatus: failure?.osStatus,
                executionOutcome: operation == "create" && failure?.notStarted != true ? .unknown : .failed)
        }
    }

    /// 纯文本 → 提醒（标题 + 备注）：首个非空行作标题，其余行作备注。
    static func content(fromPlainText text: String) -> (name: String, body: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let titleIndex = lines.firstIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let titleIndex else { return (name: "Jotway", body: "") }
        let name = lines[titleIndex].trimmingCharacters(in: .whitespaces)
        lines.removeSubrange(0...titleIndex)
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (name: name, body: body)
    }

    /// Pure request validation and component conversion, with no EventKit access.
    static func validateCreateRequest(_ request: Request) throws -> DateComponents? {
        guard request.operation == "create", !request.requestID.isEmpty,
              request.listID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              request.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw Failure(message: L10n.text("error.reminders.invalid_due"), notStarted: true, kind: .validation)
        }
        return try dueDateComponents(for: request.due)
    }

    static func dueDateComponents(for due: ReminderDue) throws -> DateComponents? {
        guard due.isValid else {
            throw Failure(message: L10n.text("error.reminders.invalid_due"), notStarted: true, kind: .validation)
        }
        var calendar = Calendar(identifier: .gregorian)
        switch due {
        case .none:
            return nil
        case .dateOnly(let year, let month, let day):
            // A floating date has no time-zone, hour, minute, or second components.
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            return DateComponents(calendar: calendar, year: year, month: month, day: day)
        case .dateTime(let instant, let timeZoneID):
            guard let timeZone = TimeZone(identifier: timeZoneID) else {
                throw Failure(message: L10n.text("error.reminders.invalid_due"), notStarted: true, kind: .validation)
            }
            calendar.timeZone = timeZone
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)
            components.calendar = calendar
            components.timeZone = timeZone
            return components
        }
    }

    /// 单例事件库：避免每次调用重复申请权限。EventKit 建议复用一个 store。
    @MainActor private static let store = EKEventStore()

    /// 检查提醒事项完全访问权限；只有显式授权操作才弹系统授权框。
    @MainActor
    private static func ensureAccess(allowPrompt: Bool) async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return true
        case .notDetermined where allowPrompt:
            return try await store.requestFullAccessToReminders()
        default:
            return false
        }
    }

    @MainActor
    static func run(_ request: Request) async throws -> Response {
        try Task.checkCancellation()
        let dueComponents = request.operation == "create" ? try validateCreateRequest(request) : nil
        do {
            guard try await ensureAccess(allowPrompt: request.allowAuthorizationPrompt) else {
                throw Failure(message: L10n.text("reminders.permission_denied"),
                              notStarted: true, kind: .permission)
            }
            try Task.checkCancellation()
            switch request.operation {
            case "lists":
                let writable = store.calendars(for: .reminder)
                    .filter { $0.allowsContentModifications }
                let defaultID = store.defaultCalendarForNewReminders()?.calendarIdentifier
                let ordered = writable.filter { $0.calendarIdentifier == defaultID }
                    + writable.filter { $0.calendarIdentifier != defaultID }
                let lists = ordered.map { calendar -> Destination in
                    let name = (calendar.source?.title).map { $0 + " / " + calendar.title } ?? calendar.title
                    return Destination(id: calendar.calendarIdentifier, name: name)
                }
                return Response(version: 1, requestID: request.requestID, status: "ok", lists: lists)

            case "create":
                guard let listID = request.listID,
                      let calendar = store.calendar(withIdentifier: listID),
                      calendar.allowsContentModifications else {
                    throw Failure(message: L10n.text("destination.changed"), notStarted: true, kind: .destination)
                }
                guard let name = request.name else {
                    throw Failure(message: L10n.text("error.reminders.invalid_due"), notStarted: true, kind: .validation)
                }
                let reminder = EKReminder(eventStore: store)
                reminder.calendar = calendar
                reminder.title = name
                if let body = request.body, !body.isEmpty { reminder.notes = body }
                reminder.dueDateComponents = dueComponents
                try store.save(reminder, commit: true)
                return Response(version: 1, requestID: request.requestID, status: "ok",
                                reminderID: reminder.calendarItemIdentifier,
                                listID: reminder.calendar.calendarIdentifier)

            default:
                throw Failure(message: L10n.text("reminders.unsupported_operation"))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as Failure {
            throw failure
        } catch {
            // EventKit 抛错说明写入未落地，可直接重试。
            let error = error as NSError
            let kind: Failure.Kind = error.domain == EKErrorDomain
                && error.code == EKError.Code.eventStoreNotAuthorized.rawValue ? .permission : .operation
            throw Failure(message: error.localizedDescription, notStarted: true,
                          osStatus: error.code, kind: kind)
        }
    }
}
