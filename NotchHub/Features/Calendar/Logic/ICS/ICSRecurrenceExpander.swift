import Foundation

/// Expands an RRULE (DAILY / WEEKLY / MONTHLY / YEARLY with INTERVAL, COUNT, UNTIL, BYDAY, BYMONTHDAY,
/// BYMONTH, BYSETPOS) into occurrence start dates overlapping a window. Expansion happens in the zone of
/// DTSTART so wall-clock times survive DST changes.
enum ICSRecurrenceExpander {
    /// Safety net against pathological rules (e.g. a daily rule with an impossible BYMONTHDAY filter).
    static let maxPeriods = 20_000
    private static let daysPerWeek = 7

    static func occurrences(
        of start: ICSDateTime,
        rule: ICSRecurrenceRule,
        duration: TimeInterval,
        excluding exceptions: Set<Int>,
        in window: DateInterval
    ) -> [Date] {
        let expansion = Expansion(start: start, rule: rule)
        var results: [Date] = []
        var produced = 0
        let firstPeriod = rule.count == nil ? expansion.periodsToSkip(before: window.start) : 0

        for period in firstPeriod..<(firstPeriod + maxPeriods) {
            guard let anchor = expansion.anchor(forPeriod: period), anchor < window.end else { break }
            for date in expansion.candidates(inPeriodStartingAt: anchor) where date >= start.date {
                if let until = rule.until, date > until { return results }
                produced += 1
                if let count = rule.count, produced > count { return results }
                if date >= window.end { return results }
                if exceptions.contains(Self.key(date)) { continue }
                if date >= window.start || date.addingTimeInterval(max(duration, 0)) > window.start {
                    results.append(date)
                }
            }
        }
        return results
    }

    /// Key used to match EXDATE / RECURRENCE-ID values against occurrences.
    static func key(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded())
    }
}

private struct Expansion {
    let rule: ICSRecurrenceRule
    let calendar: Calendar
    let startDate: Date
    let time: DateComponents
    let startYear: Int
    let startMonth: Int
    let startDay: Int
    let startWeekday: Int

    init(start: ICSDateTime, rule: ICSRecurrenceRule) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = start.timeZone
        calendar.firstWeekday = rule.weekStart
        self.calendar = calendar
        self.rule = rule
        startDate = start.date
        time = calendar.dateComponents([.hour, .minute, .second], from: start.date)
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: start.date)
        startYear = parts.year ?? 1970
        startMonth = parts.month ?? 1
        startDay = parts.day ?? 1
        startWeekday = parts.weekday ?? 1
    }

    // MARK: Periods

    func periodsToSkip(before date: Date) -> Int {
        guard date > startDate else { return 0 }
        let start = calendar.startOfDay(for: startDate)
        let elapsed: Int?
        switch rule.frequency {
        case .daily: elapsed = calendar.dateComponents([.day], from: start, to: date).day
        case .weekly: elapsed = calendar.dateComponents([.day], from: start, to: date).day.map { $0 / 7 }
        case .monthly: elapsed = calendar.dateComponents([.month], from: start, to: date).month
        case .yearly: elapsed = calendar.dateComponents([.year], from: start, to: date).year
        }
        return max(0, (elapsed ?? 0) / rule.interval - 1)
    }

    func anchor(forPeriod period: Int) -> Date? {
        let step = period * rule.interval
        switch rule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: step, to: calendar.startOfDay(for: startDate))
        case .weekly:
            guard let week = calendar.dateInterval(of: .weekOfYear, for: startDate)?.start else { return nil }
            return calendar.date(byAdding: .day, value: step * 7, to: week)
        case .monthly:
            guard let month = calendar.date(from: DateComponents(year: startYear, month: startMonth, day: 1)) else { return nil }
            return calendar.date(byAdding: .month, value: step, to: month)
        case .yearly:
            guard let year = calendar.date(from: DateComponents(year: startYear, month: 1, day: 1)) else { return nil }
            return calendar.date(byAdding: .year, value: step, to: year)
        }
    }

    func candidates(inPeriodStartingAt anchor: Date) -> [Date] {
        let parts = calendar.dateComponents([.year, .month, .day], from: anchor)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return [] }
        let days: [DateComponents]
        switch rule.frequency {
        case .daily:
            days = [DateComponents(year: year, month: month, day: day)].filter(matchesDailyFilters)
        case .weekly:
            days = weeklyDays(from: anchor)
        case .monthly:
            days = monthDays(year: year, month: month)
        case .yearly:
            let months = rule.byMonth.isEmpty ? [startMonth] : rule.byMonth.sorted()
            days = months.flatMap { monthDays(year: year, month: $0) }
        }
        let dates = days.compactMap(withTime).sorted()
        return applySetPosition(dates)
    }

    // MARK: Day selection

    private func weeklyDays(from weekStart: Date) -> [DateComponents] {
        let weekdays = rule.byDay.isEmpty ? [startWeekday] : rule.byDay.map(\.weekday)
        return Set(weekdays).compactMap { weekday -> DateComponents? in
            let offset = (weekday - rule.weekStart + 7) % 7
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard rule.byMonth.isEmpty || rule.byMonth.contains(parts.month ?? 0) else { return nil }
            return parts
        }
    }

    private func monthDays(year: Int, month: Int) -> [DateComponents] {
        guard
            let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
            let range = calendar.range(of: .day, in: .month, for: first)
        else { return [] }
        let count = range.count
        let weekdayOfFirst = calendar.component(.weekday, from: first)
        let weekday = { (day: Int) in (weekdayOfFirst - 1 + day - 1) % 7 + 1 }

        var selected: [Int]
        if !rule.byMonthDay.isEmpty {
            selected = rule.byMonthDay.map { $0 > 0 ? $0 : count + $0 + 1 }.filter { (1...count).contains($0) }
            if !rule.byDay.isEmpty {
                let allowed = Set(rule.byDay.map(\.weekday))
                selected = selected.filter { allowed.contains(weekday($0)) }
            }
        } else if !rule.byDay.isEmpty {
            selected = rule.byDay.flatMap { entry -> [Int] in
                let matching = (1...count).filter { weekday($0) == entry.weekday }
                guard let ordinal = entry.ordinal else { return matching }
                let index = ordinal > 0 ? ordinal - 1 : matching.count + ordinal
                return matching.indices.contains(index) ? [matching[index]] : []
            }
        } else {
            selected = startDay <= count ? [startDay] : []
        }
        return Set(selected).sorted().map { DateComponents(year: year, month: month, day: $0) }
    }

    private func matchesDailyFilters(_ day: DateComponents) -> Bool {
        if !rule.byMonth.isEmpty, !rule.byMonth.contains(day.month ?? 0) { return false }
        if !rule.byMonthDay.isEmpty, !rule.byMonthDay.contains(day.day ?? 0) { return false }
        guard !rule.byDay.isEmpty else { return true }
        guard let date = calendar.date(from: day) else { return false }
        return rule.byDay.map(\.weekday).contains(calendar.component(.weekday, from: date))
    }

    private func withTime(_ day: DateComponents) -> Date? {
        var components = day
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        return calendar.date(from: components)
    }

    private func applySetPosition(_ dates: [Date]) -> [Date] {
        guard !rule.bySetPosition.isEmpty, rule.frequency != .daily else { return dates }
        return rule.bySetPosition
            .compactMap { position -> Date? in
                let index = position > 0 ? position - 1 : dates.count + position
                return dates.indices.contains(index) ? dates[index] : nil
            }
            .sorted()
    }
}
