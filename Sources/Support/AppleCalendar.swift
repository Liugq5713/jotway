import EventKit
import Foundation

/// 通过 EventKit 直接读写系统日历数据库——不经 Apple Events，日历 App 无需运行。
///
/// 走"日历数据访问"权限（`requestFullAccessToEvents`，TCC 独立于 Automation），
/// 沙盒需 `com.apple.security.personal-information.calendars`（已与提醒事项共用）+
/// Info.plist 的 `NSCalendarsFullAccessUsageDescription`。对外接口与 `AppleReminders` 同构。
enum AppleCalendar {
    struct Destination: Codable, Equatable, Sendable, Identifiable {
        let id: String
        let name: String
    }

    struct Request: Sendable {
        let requestID: String
        /// "calendars"（读账号/日历）或 "create"（建日程）。
        let operation: String
        var calendarID: String?
        /// 日程标题（event title）。
        var title: String?
        /// 日程备注（event notes）；为空则不写。
        var body: String?
        /// Required for create; frozen by the action plan.
        var schedule: CalendarSchedule?
    }

    struct Response: Sendable {
        var version: Int
        var requestID: String?
        var status: String
        var calendars: [Destination]?
        var eventID: String?
        var calendarID: String?
        var message: String?
        /// 失败时的底层错误码（EventKit / EKError），用于诊断日志。
        var osStatus: Int?
    }

    struct Failure: LocalizedError {
        enum Kind: Sendable { case operation, validation }
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
        if failure?.kind == .validation {
            return ActionFailure(localized: "error.calendar.invalid_schedule", code: .validation,
                                 osStatus: failure?.osStatus, executionOutcome: .failed)
        }
        return ActionFailure(localized: operation == "calendars" ? "error.calendar.no_calendars" : "error.calendar.create_failed",
            code: .processFailed, osStatus: failure?.osStatus,
            executionOutcome: operation == "create" && failure?.notStarted != true ? .unknown : .failed)
    }

    /// Pure validation, before touching EventKit or requesting access. No missing value is repaired.
    static func validateCreateRequest(_ request: Request) throws -> CalendarSchedule {
        guard request.operation == "create", !request.requestID.isEmpty,
              request.calendarID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              request.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              let schedule = request.schedule, schedule.isValid else {
            throw Failure(message: L10n.text("error.calendar.invalid_schedule"), notStarted: true, kind: .validation)
        }
        return schedule
    }

    /// 单例事件库：避免每次调用重复申请权限。EventKit 建议复用一个 store（与提醒事项各自独立）。
    @MainActor private static let store = EKEventStore()

    /// 确保已拿到日历完全访问权限；未决时弹系统授权框。
    @MainActor
    private static func ensureAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .notDetermined:
            return try await store.requestFullAccessToEvents()
        default:
            return false
        }
    }

    @MainActor
    static func run(_ request: Request) async throws -> Response {
        try Task.checkCancellation()
        let schedule = request.operation == "create" ? try validateCreateRequest(request) : nil
        guard try await ensureAccess() else {
            throw Failure(message: L10n.text("calendar.permission_denied"))
        }
        do {
            switch request.operation {
            case "calendars":
                let calendars = store.calendars(for: .event)
                    .filter { $0.allowsContentModifications }
                    .map { calendar -> Destination in
                        let name = (calendar.source?.title).map { $0 + " / " + calendar.title } ?? calendar.title
                        return Destination(id: calendar.calendarIdentifier, name: name)
                    }
                return Response(version: 1, requestID: request.requestID, status: "ok", calendars: calendars)

            case "create":
                guard let calendarID = request.calendarID,
                      let calendar = store.calendar(withIdentifier: calendarID),
                      calendar.allowsContentModifications else {
                    throw Failure(message: L10n.text("destination.changed"))
                }
                guard let title = request.title, let schedule else {
                    throw Failure(message: L10n.text("error.calendar.invalid_schedule"), notStarted: true, kind: .validation)
                }
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                event.title = title
                if let body = request.body, !body.isEmpty { event.notes = body }
                event.startDate = schedule.start
                event.endDate = schedule.end
                event.timeZone = TimeZone(identifier: schedule.timeZoneID)
                try store.save(event, span: .thisEvent, commit: true)
                return Response(version: 1, requestID: request.requestID, status: "ok",
                                eventID: event.eventIdentifier,
                                calendarID: event.calendar?.calendarIdentifier)

            default:
                throw Failure(message: L10n.text("calendar.unsupported_operation"))
            }
        } catch let failure as Failure {
            throw failure
        } catch {
            // EventKit 抛错说明写入未落地，可直接重试。
            throw Failure(message: error.localizedDescription, notStarted: true,
                          osStatus: (error as NSError).code)
        }
    }
}
