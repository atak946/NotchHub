import Foundation

/// Parses iCalendar DATE, DATE-TIME, DURATION and RRULE values.
enum ICSValueParser {
    private static let dateLength = 8
    private static let dateTimeLength = 15
    private static let utcSuffix: Character = "Z"
    private static let weekdayCodes: [String: Int] = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

    // MARK: - Dates

    /// - Parameters:
    ///   - value: `20260310`, `20260310T090000`, `20260310T090000Z`.
    ///   - tzid: TZID parameter, resolved with `ICSTimeZoneResolver`; floating times use `fallbackZone`.
    static func dateTime(
        _ value: String,
        tzid: String?,
        customOffsets: [String: Int],
        fallbackZone: TimeZone = .current
    ) -> ICSDateTime? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let digits = Array(trimmed)
        if digits.count == dateLength {
            guard let parts = numbers(digits, ranges: [0..<4, 4..<6, 6..<8]) else { return nil }
            let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
            return make(components, zone: fallbackZone, isAllDay: true)
        }
        guard digits.count >= dateTimeLength, digits[dateLength] == "T",
              let parts = numbers(digits, ranges: [0..<4, 4..<6, 6..<8, 9..<11, 11..<13, 13..<15])
        else { return nil }
        let isUTC = digits.count > dateTimeLength && digits[dateTimeLength] == utcSuffix
        let zone: TimeZone
        if isUTC {
            zone = TimeZone(identifier: "UTC") ?? fallbackZone
        } else if let tzid, let resolved = ICSTimeZoneResolver.timeZone(for: tzid, customOffsets: customOffsets) {
            zone = resolved
        } else {
            zone = fallbackZone
        }
        let components = DateComponents(
            year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4], second: parts[5]
        )
        return make(components, zone: zone, isAllDay: false)
    }

    /// Comma-separated list (EXDATE, RDATE).
    static func dateTimes(_ value: String, tzid: String?, customOffsets: [String: Int]) -> [ICSDateTime] {
        value.split(separator: ",").compactMap { dateTime(String($0), tzid: tzid, customOffsets: customOffsets) }
    }

    // MARK: - Duration

    /// `P1D`, `PT1H30M`, `-PT15M`, `P2W`, `P1DT2H`.
    static func duration(_ value: String) -> TimeInterval? {
        var text = Substring(value.trimmingCharacters(in: .whitespaces).uppercased())
        var sign: Double = 1
        if text.first == "-" { sign = -1; text = text.dropFirst() } else if text.first == "+" { text = text.dropFirst() }
        guard text.first == "P" else { return nil }
        text = text.dropFirst()

        var total: Double = 0
        var number = ""
        var isTimePart = false
        for character in text {
            if character.isNumber {
                number.append(character)
                continue
            }
            if character == "T" { isTimePart = true; continue }
            guard let amount = Double(number) else { return nil }
            number = ""
            switch (character, isTimePart) {
            case ("W", false): total += amount * 7 * 86_400
            case ("D", false): total += amount * 86_400
            case ("H", true): total += amount * 3600
            case ("M", true): total += amount * 60
            case ("S", true): total += amount
            default: return nil
            }
        }
        return number.isEmpty ? sign * total : nil
    }

    // MARK: - RRULE

    static func recurrenceRule(_ value: String, tzid: String?, customOffsets: [String: Int]) -> ICSRecurrenceRule? {
        var fields: [String: String] = [:]
        for part in value.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            fields[pair[0].uppercased()] = pair[1]
        }
        guard let frequency = fields["FREQ"].flatMap({ ICSFrequency(rawValue: $0.uppercased()) }) else { return nil }

        var rule = ICSRecurrenceRule(frequency: frequency)
        if let interval = fields["INTERVAL"].flatMap(Int.init), interval > 0 { rule.interval = interval }
        if let count = fields["COUNT"].flatMap(Int.init), count > 0 { rule.count = count }
        if let until = fields["UNTIL"] {
            rule.until = untilDate(until, tzid: tzid, customOffsets: customOffsets)
        }
        rule.byDay = (fields["BYDAY"] ?? "").split(separator: ",").compactMap { weekdayRule(String($0)) }
        rule.byMonthDay = integers(fields["BYMONTHDAY"])
        rule.byMonth = integers(fields["BYMONTH"]).filter { (1...12).contains($0) }
        rule.bySetPosition = integers(fields["BYSETPOS"])
        if let start = fields["WKST"].flatMap({ weekdayCodes[$0.uppercased()] }) { rule.weekStart = start }
        return rule
    }

    static func weekdayRule(_ text: String) -> ICSWeekdayRule? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.count >= 2, let weekday = weekdayCodes[String(trimmed.suffix(2))] else { return nil }
        let ordinalText = trimmed.dropLast(2)
        if ordinalText.isEmpty { return ICSWeekdayRule(weekday: weekday, ordinal: nil) }
        guard let ordinal = Int(ordinalText), ordinal != 0 else { return nil }
        return ICSWeekdayRule(weekday: weekday, ordinal: ordinal)
    }

    // MARK: - Private

    /// UNTIL is inclusive; a date-only UNTIL covers the whole day.
    private static func untilDate(_ value: String, tzid: String?, customOffsets: [String: Int]) -> Date? {
        guard let parsed = dateTime(value, tzid: tzid, customOffsets: customOffsets) else { return nil }
        guard parsed.isAllDay else { return parsed.date }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = parsed.timeZone
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: parsed.date)
    }

    private static func integers(_ text: String?) -> [Int] {
        (text ?? "").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 != 0 }
    }

    private static func numbers(_ characters: [Character], ranges: [Range<Int>]) -> [Int]? {
        var result: [Int] = []
        for range in ranges {
            guard range.upperBound <= characters.count, let value = Int(String(characters[range])) else { return nil }
            result.append(value)
        }
        return result
    }

    private static func make(_ components: DateComponents, zone: TimeZone, isAllDay: Bool) -> ICSDateTime? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let date = calendar.date(from: components) else { return nil }
        return ICSDateTime(date: date, isAllDay: isAllDay, timeZone: zone)
    }
}
