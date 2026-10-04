import Foundation

/// Display derives only from the frozen values also captured by the write request.
struct ActionPlanSummaryFormatter {
    let targetName: String
    let timeText: String
    let detail: String

    init(summary: ActionPlanSummary, context: ScheduleContext) {
        let zoneID: String
        switch summary {
        case .reminder(_, _, .dateTime(_, let timeZoneID), _): zoneID = timeZoneID
        case .calendar(_, _, let schedule, _): zoneID = schedule.timeZoneID
        default: zoneID = context.timeZoneID
        }
        // Executor validates the summary against the resolved schedule before publishing it.
        guard let zone = TimeZone(identifier: zoneID) else {
            targetName = ""
            timeText = L10n.text("schedule.issue.unsupported_time_zone")
            detail = timeText
            return
        }
        var calendar = context.calendar
        calendar.timeZone = zone
        func format(_ instant: Date, pattern: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = zone
            formatter.dateFormat = pattern
            return formatter.string(from: instant)
        }
        func clock(_ instant: Date) -> String {
            let seconds = calendar.component(.second, from: instant)
            return format(instant, pattern: seconds == 0 ? "HH:mm" : "HH:mm:ss")
        }
        func dateTime(_ instant: Date) -> String {
            "\(format(instant, pattern: "yyyy-MM-dd")) \(clock(instant))"
        }
        switch summary {
        case .reminder(_, let name, let due, _):
            targetName = name
            switch due {
            case .none:
                timeText = L10n.text("schedule.no_due_date")
            case .dateOnly(let year, let month, let day):
                timeText = String(format: "%04d-%02d-%02d", year, month, day)
                    + " · " + L10n.text("schedule.date_only")
            case .dateTime(let instant, _):
                timeText = dateTime(instant)
            }
        case .calendar(_, let name, let schedule, _):
            targetName = name
            let sameDay = calendar.isDate(schedule.start, inSameDayAs: schedule.end)
            let end = sameDay ? clock(schedule.end) : dateTime(schedule.end)
            let duration = schedule.endSource == .defaultOneHour ? " · " + L10n.text("schedule.default_hour") : ""
            timeText = "\(dateTime(schedule.start))–\(end)\(duration)"
        }
        detail = "\(targetName) · \(timeText). \(L10n.text("schedule.timezone", zoneID))"
    }
}
