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
        /// 开始时间；缺省回退当前时刻。
        var start: Date?
        /// 结束时间；缺省或早于开始时回退开始 + 1 小时。
        var end: Date?
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
        let message: String
        /// 仅能证明写入根本未开始的错误可直接重试。
        var notStarted = false
        /// 失败时的底层错误码，用于诊断日志。
        var osStatus: Int? = nil
        var errorDescription: String? { message }
    }

    /// 默认日程时长：原文没提结束时间时给 1 小时。
    static let defaultDuration: TimeInterval = 3600

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
                guard let title = request.title, !title.isEmpty else {
                    throw Failure(message: L10n.text("error.empty_content"))
                }
                let start = request.start ?? Date()
                let end = request.end.map { $0 > start ? $0 : start.addingTimeInterval(defaultDuration) }
                    ?? start.addingTimeInterval(defaultDuration)
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                event.title = title
                if let body = request.body, !body.isEmpty { event.notes = body }
                event.startDate = start
                event.endDate = end
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
