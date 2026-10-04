import Foundation

/// A deliberately bounded grammar. Every temporal clue must be covered by a parsed token;
/// ordinary body words are retained and never interpreted by an AI or a detector fallback.
enum ScheduleResolver {
    static func resolve(_ text: String, context: ScheduleContext) -> TimeResolution {
        do { return try Parser(text: text, context: context).resolve() }
        catch let issue as TimeInputIssue { return .needsInput(issue) }
        catch { return .needsInput(TimeInputIssue(code: .internalFailure).inContext(context)) }
    }

    private struct Match {
        let range: NSRange
        let values: [String?]
        subscript(_ index: Int) -> String { values[index] ?? "" }
    }

    private struct Day {
        let year: Int
        let month: Int
        let day: Int
        let source: ScheduleSource
        let range: NSRange
    }

    private struct Clock {
        let hour: Int
        let minute: Int
        let period: String?
        let chineseNumber: Bool
        let range: NSRange
    }

    private struct DurationToken {
        let seconds: TimeInterval
        let range: NSRange
    }

    private struct Parser {
        let text: String
        let context: ScheduleContext
        private var source: NSString { text as NSString }
        private var calendar: Calendar { context.calendar }
        private let number = #"(?<![0-9零〇一二两三四五六七八九十百千+−-])[+−-]?(?:[0-9]+|[零〇一二两三四五六七八九十百千]+)"#

        private func matches(_ pattern: String) throws -> [Match] {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
                Match(range: match.range, values: (0..<match.numberOfRanges).map { index in
                    let range = match.range(at: index)
                    return range.location == NSNotFound ? nil : source.substring(with: range)
                })
            }
        }

        private func issue(_ code: TimeInputIssue.Code, _ range: NSRange? = nil) -> TimeInputIssue {
            TimeInputIssue(code: code, fragment: range.map { source.substring(with: $0) }).inContext(context)
        }

        private func overlaps(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
            ranges.contains { NSIntersectionRange(range, $0).length > 0 }
        }

        private func integers(_ value: String) -> Int? {
            if let value = Int(value.replacingOccurrences(of: "−", with: "-")) { return value }
            let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3,
                                            "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
            let units: [Character: Int] = ["十": 10, "百": 100, "千": 1_000]
            var result = 0
            var digit: Int?
            var lastUnit = 10_000
            for character in value {
                if let next = digits[character] {
                    guard digit == nil || digit == 0 else { return nil }
                    digit = next
                } else if let unit = units[character], unit < lastUnit {
                    result += (digit ?? 1) * unit
                    digit = nil
                    lastUnit = unit
                } else { return nil }
            }
            return value.isEmpty ? nil : result + (digit ?? 0)
        }

        private func day(from date: Date, source: ScheduleSource, range: NSRange) throws -> Day {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = parts.year, let month = parts.month, let day = parts.day,
                  ScheduleValidation.validDate(year: year, month: month, day: day) else { throw issue(.invalidDate, range) }
            return Day(year: year, month: month, day: day, source: source, range: range)
        }

        private func dateOnly(_ day: Day) throws -> Date {
            guard ScheduleValidation.validDate(year: day.year, month: day.month, day: day.day),
                  let value = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) else {
                throw issue(.invalidDate, day.range)
            }
            let parts = calendar.dateComponents([.year, .month, .day], from: value)
            guard parts.year == day.year, parts.month == day.month, parts.day == day.day else {
                throw issue(.invalidDate, day.range)
            }
            return value
        }

        private func instant(_ day: Day, _ clock: Clock, inheriting period: String? = nil) throws -> Date {
            var hour = clock.hour
            let period = clock.period ?? (clock.hour <= 12 ? period : nil)
            guard (0...59).contains(clock.minute) else { throw issue(.invalidTime, clock.range) }
            if let period {
                guard (1...12).contains(hour) else { throw issue(.invalidTime, clock.range) }
                hour = hour % 12 + (["下午", "pm"].contains(period) ? 12 : 0)
            } else {
                guard (0...23).contains(hour) else { throw issue(.invalidTime, clock.range) }
                guard !clock.chineseNumber || hour >= 13 else { throw issue(.ambiguous, clock.range) }
            }
            let base = try dateOnly(day)
            let parts = DateComponents(year: day.year, month: day.month, day: day.day,
                                       hour: hour, minute: clock.minute, second: 0)
            let beforeDay = calendar.startOfDay(for: base).addingTimeInterval(-1)
            guard let first = calendar.nextDate(after: beforeDay, matching: parts, matchingPolicy: .strict,
                                               repeatedTimePolicy: .first),
                  let last = calendar.nextDate(after: beforeDay, matching: parts, matchingPolicy: .strict,
                                              repeatedTimePolicy: .last) else { throw issue(.daylightSavingTime, clock.range) }
            guard first == last else { throw issue(.daylightSavingTime, clock.range) }
            let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: first)
            guard actual.year == day.year, actual.month == day.month, actual.day == day.day,
                  actual.hour == hour, actual.minute == clock.minute, actual.second == 0 else {
                throw issue(.daylightSavingTime, clock.range)
            }
            return first
        }

        private func seconds(_ match: Match, numberIndex: Int, unitIndex: Int) throws -> TimeInterval {
            guard let quantity = integers(match[numberIndex]), quantity > 0,
                  quantity <= Int.max / 3_600 else { throw issue(.invalidRange, match.range) }
            let unit = match[unitIndex].lowercased()
            return TimeInterval(quantity) * (unit.contains("hour") || unit == "小时" ? 3_600 : 60)
        }

        func resolve() throws -> TimeResolution {
            guard context.referenceDate.timeIntervalSinceReferenceDate.isFinite else { throw issue(.internalFailure) }
            var consumed: [NSRange] = []
            let timeZonePattern = #"北京时间|上海时间|纽约时间|伦敦时间|时区|\b(?:UTC|GMT|PST|PDT|CST|CDT|EST|EDT|MST|MDT|CET|CEST|JST|AEST|AEDT)\b|[+-][0-9]{2}:?[0-9]{2}\b|(?<=[0-9])Z\b|\b(?:Asia|America|Europe|Australia)/[A-Za-z_]+"#
            if let found = try matches(timeZonePattern).first { throw issue(.unsupportedTimeZone, found.range) }
            let recurrencePattern = #"每(?:天|日|周|星期|月|年|隔|逢)|重复|循环|\b(?:every|daily|weekly|monthly|yearly|annually|recurring|repeat)\b"#
            if let found = try matches(recurrencePattern).first { throw issue(.recurrence, found.range) }
            let vaguePattern = #"下班后|稍后|待会|过会|月底|月末|月初|年底|年末|年初|十一假后|假期后|节假日|农历|阴历|春节|国庆|中秋|清明|端午|圣诞|周末|今晚|今早|明早|明晚|大后天|大前天|下下周|上上周|下下星期|上上星期|今年|明年|后年|去年|下个月|上个月|这个月|下次|以后|午夜|黎明|正午|午后|全天|整天|大约|大概|差不多|左右|前后|约(?=\s*[0-9零〇一二两三四五六七八九十上午下])|一会儿|尽快|某天|\b(?:after\s+work|later|sometime|eventually|soon|around|about|approximately|all[ -]day|tonight|morning|afternoon|evening|noon|midnight|weekend|holiday|christmas|easter|thanksgiving|lunar)\b"#
            if let found = try matches(vaguePattern).first { throw issue(.unsupportedExpression, found.range) }

            var relative: [DurationToken] = []
            for pattern in ["(\(number))\\s*(分钟|小时)\\s*后", "\\bin\\s+(\(number))\\s*(minutes?|hours?)\\b"] {
                for found in try matches(pattern) {
                    guard !overlaps(found.range, consumed) else { continue }
                    relative.append(.init(seconds: try seconds(found, numberIndex: 1, unitIndex: 2), range: found.range))
                    consumed.append(found.range)
                }
            }
            let now = try matches(#"现在|\bnow\b"#)
            consumed += now.map(\.range)

            var days: [Day] = []
            for pattern in [#"(?<![0-9+−-])[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}(?![0-9])"#,
                            #"(?<![0-9+−-])[0-9]{4}年\s*[0-9]{1,2}月\s*[0-9]{1,2}[日号]"#] {
                for found in try matches(pattern) {
                    let numbers = found[0].split { !$0.isNumber }.compactMap { Int($0) }
                    guard numbers.count == 3,
                          ScheduleValidation.validDate(year: numbers[0], month: numbers[1], day: numbers[2]) else {
                        throw issue(.invalidDate, found.range)
                    }
                    days.append(Day(year: numbers[0], month: numbers[1], day: numbers[2], source: .absoluteDate, range: found.range))
                    consumed.append(found.range)
                }
            }
            for found in try matches(#"今天|明天|后天|昨天|前天|\b(?:today|tomorrow|yesterday)\b"#) {
                let offset: Int
                switch found[0].lowercased() {
                case "今天", "today": offset = 0
                case "明天", "tomorrow": offset = 1
                case "后天": offset = 2
                case "昨天", "yesterday": offset = -1
                default: offset = -2
                }
                guard let date = calendar.date(byAdding: .day, value: offset, to: context.referenceDate) else {
                    throw issue(.invalidDate, found.range)
                }
                days.append(try day(from: date, source: .relativeDate, range: found.range))
                consumed.append(found.range)
            }
            let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
            for pattern in [#"(本周|下周|本星期|下星期)([一二三四五六日天])"#,
                            #"\b(this|next)\s+(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\b"#] {
                for found in try matches(pattern) {
                    let dayIndex = weekdays.firstIndex(of: found[2].lowercased())
                        ?? ["一", "二", "三", "四", "五", "六", "日"].firstIndex(of: found[2])
                        ?? (found[2] == "天" ? 6 : nil)
                    guard let dayIndex, let week = calendar.dateInterval(of: .weekOfYear, for: context.referenceDate) else {
                        throw issue(.invalidDate, found.range)
                    }
                    let next = ["下周", "下星期", "next"].contains(found[1].lowercased())
                    guard let date = calendar.date(byAdding: .day, value: dayIndex + (next ? 7 : 0), to: week.start) else {
                        throw issue(.invalidDate, found.range)
                    }
                    days.append(try day(from: date, source: .relativeDate, range: found.range))
                    consumed.append(found.range)
                }
            }
            days.sort { $0.range.location < $1.range.location }

            var clocks: [Clock] = []
            // Longer period-qualified forms must win over their embedded HH:mm tokens.
            for found in try matches(#"(?<![0-9:])([0-9]{1,2})(?::([0-9]{2}))?\s*(am|pm)\b"#) {
                clocks.append(Clock(hour: Int(found[1]) ?? -1, minute: Int(found[2]) ?? 0,
                    period: found[3].lowercased(), chineseNumber: false, range: found.range))
                consumed.append(found.range)
            }
            for found in try matches(#"(上午|下午)\s*([0-9]{1,2}):([0-9]{2})(?![0-9:])"#) {
                guard !overlaps(found.range, consumed) else { continue }
                clocks.append(Clock(hour: Int(found[2]) ?? -1, minute: Int(found[3]) ?? -1,
                    period: found[1], chineseNumber: false, range: found.range))
                consumed.append(found.range)
            }
            for found in try matches(#"(?:(上午|下午)\s*)?([0-9]{1,2}|[零〇一二两三四五六七八九十]+)[点时](?:(半)|([0-9]{1,2}|[零〇一二两三四五六七八九十]+)分?)?"#) {
                guard !overlaps(found.range, consumed) else { continue }
                clocks.append(Clock(hour: integers(found[2]) ?? -1,
                    minute: found[3] == "半" ? 30 : found[4].isEmpty ? 0 : integers(found[4]) ?? -1,
                    period: found[1].isEmpty ? nil : found[1], chineseNumber: Int(found[2]) == nil, range: found.range))
                consumed.append(found.range)
            }
            for found in try matches(#"(?<![0-9:])([0-9]{1,2}):([0-9]{2})(?![0-9:])"#) {
                guard !overlaps(found.range, consumed) else { continue }
                clocks.append(Clock(hour: Int(found[1]) ?? -1, minute: Int(found[2]) ?? -1,
                    period: nil, chineseNumber: false, range: found.range))
                consumed.append(found.range)
            }
            clocks.sort { $0.range.location < $1.range.location }

            var durations: [DurationToken] = []
            for pattern in ["(?:(?:持续|时长|历时|共)\\s*)?(\(number))\\s*(?:个)?(小时|分钟)", "\\b(?:for\\s+)?(\(number))\\s*(minutes?|hours?)\\b"] {
                for found in try matches(pattern) {
                    guard !overlaps(found.range, consumed) else { continue }
                    durations.append(.init(seconds: try seconds(found, numberIndex: 1, unitIndex: 2), range: found.range))
                    consumed.append(found.range)
                }
            }
            guard relative.count <= 1, now.count <= 1, durations.count <= 1, days.count <= 2, clocks.count <= 2 else {
                throw issue(.multipleTimes)
            }
            if !relative.isEmpty || !now.isEmpty {
                guard relative.count + now.count == 1, days.isEmpty, clocks.isEmpty else {
                    throw issue(.multipleTimes)
                }
            }

            var rangeMention = false
            // Range punctuation in dates was consumed above. Connectors are meaningful once a
            // time/date exists; an ordinary sentence such as “去到北京” has no temporal clue.
            let hasPoint = !clocks.isEmpty || !days.isEmpty || !relative.isEmpty || !now.isEmpty
            let connectorCandidates = hasPoint ? try matches(#"到|至|[–—~～]|(?<=[0-9])\s*-\s*|\b(?:to|until|through)\b"#) : []
            let connectors = try connectorCandidates.filter { candidate in
                guard !overlaps(candidate.range, consumed) else { return false }
                let word = candidate[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard word == "to" || word == "到" else { return true }
                guard clocks.contains(where: { NSMaxRange($0.range) <= candidate.range.location }) else { return false }
                if clocks.contains(where: { $0.range.location > candidate.range.location }) { return true }
                let following = source.substring(from: NSMaxRange(candidate.range))
                let ending = try NSRegularExpression(pattern: #"^\s*(?:[0-9零〇一二两三四五六七八九十上午下今明后]|待定|未定|TBD\b|unknown\b|evening\b|night\b)"#,
                                                     options: [.caseInsensitive])
                return ending.firstMatch(in: following, range: NSRange(location: 0, length: (following as NSString).length)) != nil
            }
            if !connectors.isEmpty {
                guard connectors.count == 1, clocks.count == 2,
                      connectors[0].range.location >= NSMaxRange(clocks[0].range),
                      connectors[0].range.location < clocks[1].range.location else {
                    throw issue(.invalidRange, connectors.first?.range)
                }
                rangeMention = true
                consumed.append(connectors[0].range)
            }
            if clocks.count == 2, !rangeMention { throw issue(.multipleTimes) }
            if days.count == 2 {
                guard rangeMention, clocks.count == 2, days[0].range.location < clocks[0].range.location,
                      days[1].range.location > clocks[0].range.location,
                      days[1].range.location < clocks[1].range.location else { throw issue(.multipleTimes) }
            }

            // These patterns are intentionally broader than the accepted grammar. A malformed,
            // partial or unsupported time cannot silently become an undated reminder.
            let cluePatterns = [
                #"(?<![0-9])[0-9]{1,4}[-/.][0-9]{1,2}(?:[-/.][0-9]{0,4})?"#,
                #"[0-9]{1,2}:[0-9]{0,2}(?::[0-9]*)?"#,
                #"[0-9零〇一二两三四五六七八九十百千]+\s*(?:年|月|日|号|天|周|星期|点|时|分钟|小时|钟头|刻钟|刻|分|秒)(?:[0-9零〇一二两三四五六七八九十]+[日号]?)?"#,
                #"小时|分钟|秒钟|钟头|刻钟|上午|下午|早上|早晨|凌晨|中午|傍晚|晚上|今天|明天|后天|昨天|前天|现在|(?:本|下|上)?(?:周|星期|礼拜)[一二三四五六日天]|(?:本|下|上)(?:周|星期)"#,
                #"\b(?:today|tomorrow|yesterday|now|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Tues|Wed|Thu|Thur|Thurs|Fri|Sat|Sun|am|pm|minutes?|hours?|seconds?|days?|weeks?|months?|years?|before|after)\b"#,
                #"\b(?:January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\b(?:\s+[0-9]+(?:st|nd|rd|th)?)?"#,
                #"半\s*(?:个)?(?:小时|分钟|钟头)|(?:数|几)\s*(?:天|分钟|小时)|待定|未定|\b(?:TBD|duration|ending|ends|end\s+time)\b"#,
                #"[0-9零〇一二两三四五六七八九十百千]+\s*(?:分钟|小时|天)(?:之|以)?[前后]"#,
                #"[0-9]+\s*(?:min|mins|minutes?|h|hr|hrs|hours?|sec|seconds?)\b|\b[0-9]{4}-W[0-9]+\b"#,
                #"(?:[0-9]:[0-9]{2}|[点时](?:半)?)(?:之前|之后|以前|以后|前|后)"#,
                #"结束|到(?:吃完|饭后|下班|睡前)|持续|时长|历时|半天|(?:分钟|小时)\s*半|\bto\s+be\s+(?:decided|determined|confirmed)\b|\bfor\s+(?:a\s+while|some\s+time|a\s+bit)\b|\b(?:hours?|minutes?)\s+(?:and\s+)?(?:a\s+)?half\b"#
            ]
            // A range introducer belongs to the same parsed range, never a second event.
            if rangeMention {
                for from in try matches(#"\bfrom\b"#) where from.range.location < clocks[0].range.location {
                    consumed.append(from.range)
                }
            }
            if hasPoint, let offset = try matches(#"[+-][0-9]{2}\b"#).first(where: { !overlaps($0.range, consumed) }) {
                throw issue(.unsupportedTimeZone, offset.range)
            }
            if hasPoint, let alternative = try matches(#"或|\bor\b"#).first {
                throw issue(.multipleTimes, alternative.range)
            }
            var covered = Set<Int>()
            for range in consumed { covered.formUnion(range.location..<NSMaxRange(range)) }
            for pattern in cluePatterns {
                for clue in try matches(pattern) {
                    let unexplained = (clue.range.location..<NSMaxRange(clue.range)).contains { index in
                        !covered.contains(index) && !(UnicodeScalar(source.character(at: index)).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false)
                    }
                    if unexplained { throw issue(.unsupportedExpression, clue.range) }
                }
            }

            if !relative.isEmpty || !now.isEmpty {
                let start = context.referenceDate.addingTimeInterval(relative.first?.seconds ?? 0)
                let source: ScheduleSource = relative.isEmpty ? .now : .relativeInterval
                _ = try day(from: start, source: source, range: relative.first?.range ?? now[0].range)
                let end = durations.first.map { start.addingTimeInterval($0.seconds) }
                if let end, let duration = durations.first {
                    _ = try day(from: end, source: source, range: duration.range)
                }
                return .resolved(.init(start: start, precision: .dateTime, end: end,
                    endSource: end == nil ? nil : .explicitDuration, timeZoneID: context.timeZoneID, source: source))
            }
            guard let startDay = days.first else {
                if !clocks.isEmpty { throw issue(.missingDate, clocks[0].range) }
                if !durations.isEmpty { throw issue(.missingDateAndTime, durations[0].range) }
                return .noTimeMention
            }
            guard let startClock = clocks.first else {
                guard durations.isEmpty else { throw issue(.missingTime, durations[0].range) }
                let start = try dateOnly(startDay)
                guard calendar.startOfDay(for: start) >= calendar.startOfDay(for: context.referenceDate) else {
                    throw issue(.pastTime, startDay.range)
                }
                return .resolved(.init(start: start, precision: .dateOnly, end: nil, endSource: nil,
                                       timeZoneID: context.timeZoneID, source: startDay.source))
            }
            let start = try instant(startDay, startClock)
            guard start >= context.referenceDate else { throw issue(.pastTime, startClock.range) }
            var end: Date?
            var endSource: CalendarEndSource?
            if rangeMention {
                end = try instant(days.count == 2 ? days[1] : startDay, clocks[1],
                                  inheriting: days.count == 1 ? startClock.period : nil)
                endSource = .explicitEnd
                guard let end, end > start else { throw issue(.invalidRange, clocks[1].range) }
            }
            if let duration = durations.first {
                let proposedEnd = start.addingTimeInterval(duration.seconds)
                _ = try day(from: proposedEnd, source: startDay.source, range: duration.range)
                if let end {
                    guard abs(end.timeIntervalSince(proposedEnd)) < 0.001 else { throw issue(.invalidRange, duration.range) }
                } else {
                    end = proposedEnd
                    endSource = .explicitDuration
                }
            }
            return .resolved(.init(start: start, precision: .dateTime, end: end, endSource: endSource,
                                   timeZoneID: context.timeZoneID, source: startDay.source))
        }
    }
}
