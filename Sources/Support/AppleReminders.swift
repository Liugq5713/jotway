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
        /// 到期时间；非空时写入到期日+时分（默认当前时刻）。
        var due: Date?
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
        let message: String
        /// 仅能证明写入根本未开始的错误可直接重试。
        var notStarted = false
        /// 失败时的底层错误码，用于诊断日志。
        var osStatus: Int? = nil
        var errorDescription: String? { message }
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

    /// 单例事件库：避免每次调用重复申请权限。EventKit 建议复用一个 store。
    @MainActor private static let store = EKEventStore()

    /// 确保已拿到提醒事项完全访问权限；未决时弹系统授权框。
    @MainActor
    private static func ensureAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return true
        case .notDetermined:
            return try await store.requestFullAccessToReminders()
        default:
            return false
        }
    }

    @MainActor
    static func run(_ request: Request) async throws -> Response {
        guard try await ensureAccess() else {
            throw Failure(message: L10n.text("reminders.permission_denied"))
        }
        do {
            switch request.operation {
            case "lists":
                let lists = store.calendars(for: .reminder)
                    .filter { $0.allowsContentModifications }
                    .map { calendar -> Destination in
                        let name = (calendar.source?.title).map { $0 + " / " + calendar.title } ?? calendar.title
                        return Destination(id: calendar.calendarIdentifier, name: name)
                    }
                return Response(version: 1, requestID: request.requestID, status: "ok", lists: lists)

            case "create":
                guard let listID = request.listID,
                      let calendar = store.calendar(withIdentifier: listID),
                      calendar.allowsContentModifications else {
                    throw Failure(message: L10n.text("destination.changed"))
                }
                guard let name = request.name, !name.isEmpty else {
                    throw Failure(message: L10n.text("error.empty_content"))
                }
                let reminder = EKReminder(eventStore: store)
                reminder.calendar = calendar
                reminder.title = name
                if let body = request.body, !body.isEmpty { reminder.notes = body }
                if let due = request.due {
                    reminder.dueDateComponents = Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute], from: due)
                }
                try store.save(reminder, commit: true)
                return Response(version: 1, requestID: request.requestID, status: "ok",
                                reminderID: reminder.calendarItemIdentifier,
                                listID: reminder.calendar.calendarIdentifier)

            default:
                throw Failure(message: L10n.text("reminders.unsupported_operation"))
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
