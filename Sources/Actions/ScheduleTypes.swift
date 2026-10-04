import Foundation

/// All clock and calendar environment enters parsing through this immutable value.
struct ScheduleContext: Sendable, Equatable {
    let referenceDate: Date
    let timeZoneID: String

    init(referenceDate: Date, timeZone: TimeZone) {
        self.referenceDate = referenceDate
        self.timeZoneID = timeZone.identifier
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID)! }
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = timeZone
        value.firstWeekday = 2
        value.minimumDaysInFirstWeek = 4
        return value
    }

    func isCurrent(at now: Date, timeZone: TimeZone) -> Bool {
        referenceDate.timeIntervalSinceReferenceDate.isFinite && now.timeIntervalSinceReferenceDate.isFinite
            && now >= referenceDate && timeZone.identifier == timeZoneID
            && calendar.isDate(referenceDate, inSameDayAs: now)
    }
}

enum SchedulePrecision: String, Sendable, Equatable { case dateOnly, dateTime }
enum ScheduleSource: String, Sendable, Equatable { case absoluteDate, relativeDate, relativeInterval, now }
enum CalendarEndSource: String, Sendable, Equatable { case explicitEnd, explicitDuration, defaultOneHour }

struct TimeInputIssue: Error, Sendable, Equatable {
    enum Code: String, Sendable, Equatable, CaseIterable {
        case missingDateAndTime = "missing_date_and_time"
        case missingDate = "missing_date"
        case missingTime = "missing_time"
        case ambiguous
        case invalidDate = "invalid_date"
        case invalidTime = "invalid_time"
        case invalidRange = "invalid_range"
        case multipleTimes = "multiple_times"
        case recurrence
        case unsupportedTimeZone = "unsupported_time_zone"
        case unsupportedExpression = "unsupported_expression"
        case pastTime = "past_time"
        case daylightSavingTime = "daylight_saving_time"
        case singleDueRequired = "single_due_required"
        case internalFailure = "internal_failure"
        case preparationFailed = "preparation_failed"
    }

    let code: Code
    let fragment: String?
    let example: String

    init(code: Code, fragment: String? = nil, example: String = "2026-10-05 15:00") {
        self.code = code
        self.fragment = fragment
        self.example = example
    }

    var localizationKey: String { "schedule.issue.\(code.rawValue)" }
    var reasonCode: String { "time_\(code.rawValue)" }

    func inContext(_ context: ScheduleContext) -> TimeInputIssue {
        guard context.referenceDate.timeIntervalSinceReferenceDate.isFinite,
              let tomorrow = context.calendar.date(byAdding: .day, value: 1, to: context.referenceDate) else { return self }
        let parts = context.calendar.dateComponents([.year, .month, .day], from: tomorrow)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              ScheduleValidation.validDate(year: year, month: month, day: day) else { return self }
        return TimeInputIssue(code: code, fragment: fragment,
            example: String(format: "%04d-%02d-%02d 15:00", year, month, day))
    }
}

enum ReminderDue: Sendable, Equatable {
    case none
    case dateOnly(year: Int, month: Int, day: Int)
    case dateTime(instant: Date, timeZoneID: String)

    var isValid: Bool {
        switch self {
        case .none: true
        case .dateOnly(let year, let month, let day): ScheduleValidation.validDate(year: year, month: month, day: day)
        case .dateTime(let instant, let timeZoneID):
            instant.timeIntervalSinceReferenceDate.isFinite && TimeZone(identifier: timeZoneID) != nil
        }
    }
}

struct CalendarSchedule: Sendable, Equatable {
    let start: Date
    let end: Date
    let timeZoneID: String
    let endSource: CalendarEndSource

    init(start: Date, end: Date, timeZoneID: String, endSource: CalendarEndSource) throws {
        guard start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite,
              end > start, TimeZone(identifier: timeZoneID) != nil else {
            throw TimeInputIssue(code: .invalidRange)
        }
        self.start = start
        self.end = end
        self.timeZoneID = timeZoneID
        self.endSource = endSource
    }

    var isValid: Bool {
        start.timeIntervalSinceReferenceDate.isFinite && end.timeIntervalSinceReferenceDate.isFinite
            && end > start && TimeZone(identifier: timeZoneID) != nil
    }
}

struct ParsedSchedule: Sendable, Equatable {
    let start: Date
    let precision: SchedulePrecision
    let end: Date?
    let endSource: CalendarEndSource?
    let timeZoneID: String
    let source: ScheduleSource
}

enum TimeResolution: Sendable, Equatable {
    case noTimeMention
    case resolved(ParsedSchedule)
    case needsInput(TimeInputIssue)

    var reminderDue: Result<ReminderDue, TimeInputIssue> {
        switch self {
        case .noTimeMention: return .success(.none)
        case .needsInput(let issue): return .failure(issue)
        case .resolved(let parsed):
            guard parsed.end == nil, parsed.endSource == nil else {
                return .failure(.init(code: .singleDueRequired))
            }
            guard let timeZone = TimeZone(identifier: parsed.timeZoneID), parsed.start.timeIntervalSinceReferenceDate.isFinite else {
                return .failure(.init(code: .invalidDate))
            }
            if parsed.precision == .dateTime {
                return .success(.dateTime(instant: parsed.start, timeZoneID: parsed.timeZoneID))
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let parts = calendar.dateComponents([.year, .month, .day], from: parsed.start)
            guard let year = parts.year, let month = parts.month, let day = parts.day,
                  ScheduleValidation.validDate(year: year, month: month, day: day) else {
                return .failure(.init(code: .invalidDate))
            }
            return .success(.dateOnly(year: year, month: month, day: day))
        }
    }

    var calendarSchedule: Result<CalendarSchedule, TimeInputIssue> {
        switch self {
        case .noTimeMention: return .failure(.init(code: .missingDateAndTime))
        case .needsInput(let issue): return .failure(issue)
        case .resolved(let parsed):
            guard parsed.precision == .dateTime else { return .failure(.init(code: .missingTime)) }
            guard (parsed.end == nil) == (parsed.endSource == nil) else {
                return .failure(.init(code: .invalidRange))
            }
            do {
                return .success(try CalendarSchedule(start: parsed.start,
                    end: parsed.end ?? parsed.start.addingTimeInterval(3_600), timeZoneID: parsed.timeZoneID,
                    endSource: parsed.endSource ?? .defaultOneHour))
            } catch let issue as TimeInputIssue { return .failure(issue) }
            catch { return .failure(.init(code: .internalFailure)) }
        }
    }

    /// A frozen plan may expire; this method never slides its absolute values forward.
    func isCurrent(context: ScheduleContext, at now: Date, timeZone: TimeZone) -> Bool {
        guard context.isCurrent(at: now, timeZone: timeZone) else { return false }
        switch self {
        case .noTimeMention: return true
        case .needsInput: return false
        case .resolved(let parsed):
            guard parsed.timeZoneID == context.timeZoneID else { return false }
            if parsed.source == .relativeInterval || parsed.source == .now {
                guard now.timeIntervalSince(context.referenceDate) < 60 else { return false }
            }
            if parsed.source == .now { return true }
            if parsed.precision == .dateOnly {
                return context.calendar.startOfDay(for: parsed.start) >= context.calendar.startOfDay(for: now)
            }
            return parsed.start >= now
        }
    }
}

enum ScheduleValidation {
    static func validDate(year: Int, month: Int, day: Int) -> Bool {
        guard (1...9_999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: parts) else { return false }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        return actual.year == year && actual.month == month && actual.day == day
    }
}
