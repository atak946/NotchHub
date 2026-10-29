import Foundation

/// When the end-of-day summary fires: a local time, on weekdays only by default.
struct DailySummarySchedule: Equatable, Sendable {
    static let defaultHour = 18
    static let defaultMinute = 0
    /// After this long past the fire time the summary is skipped (e.g. Mac woke up at 23:00).
    static let lateWindow: TimeInterval = 3 * 60 * 60

    var hour: Int
    var minute: Int
    var weekdaysOnly: Bool

    init(hour: Int = defaultHour, minute: Int = defaultMinute, weekdaysOnly: Bool = true) {
        self.hour = hour
        self.minute = minute
        self.weekdaysOnly = weekdaysOnly
    }

    /// Fire time on `date`'s day, or `nil` on skipped days (weekends).
    func fireDate(onDayOf date: Date, calendar: Calendar) -> Date? {
        if weekdaysOnly && calendar.isDateInWeekend(date) { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
    }

    /// Next fire time strictly after `date`, looking at most two weeks ahead.
    func nextFireDate(after date: Date, calendar: Calendar) -> Date? {
        let lookahead = 14
        for offset in 0...lookahead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date),
                  let fire = fireDate(onDayOf: day, calendar: calendar),
                  fire > date
            else { continue }
            return fire
        }
        return nil
    }

    /// True once per day, inside `[fireDate, fireDate + lateWindow)`, unless already fired that day.
    func shouldFire(now: Date, lastFiredDay: String?, calendar: Calendar) -> Bool {
        guard let fire = fireDate(onDayOf: now, calendar: calendar) else { return false }
        let today = TimeLedgerDay.key(for: now, calendar: calendar)
        guard lastFiredDay != today else { return false }
        return now >= fire && now.timeIntervalSince(fire) < Self.lateWindow
    }
}

enum TimeSummaryFormatter {
    static let maxClientsInLine = 3

    static func title(totalSeconds: Int) -> String {
        "Bugün: \(InsightsDurationFormatter.short(seconds: totalSeconds)) takip edildi"
    }

    /// "Northwind 3h, Globex 2h…" — the ellipsis marks clients left out.
    static func clientLine(_ totals: [ClientTotal], limit: Int = maxClientsInLine) -> String {
        let shown = totals.prefix(limit).map { "\($0.client) \(InsightsDurationFormatter.short(seconds: $0.seconds))" }
        let suffix = totals.count > limit ? "…" : ""
        return shown.joined(separator: ", ") + suffix
    }

    /// "Today: 6h 40m tracked — Northwind 3h, Globex 2h…"
    static func line(totalSeconds: Int, totals: [ClientTotal]) -> String {
        let clients = clientLine(totals)
        return clients.isEmpty ? title(totalSeconds: totalSeconds) : "\(title(totalSeconds: totalSeconds)) — \(clients)"
    }

    /// Full multi-line text for the clipboard.
    static func clipboardText(day: String, totalSeconds: Int, totals: [ClientTotal]) -> String {
        let header = "\(day): \(InsightsDurationFormatter.short(seconds: totalSeconds)) takip edildi"
        let lines = totals.map { "- \($0.client): \(InsightsDurationFormatter.short(seconds: $0.seconds))" }
        return ([header] + lines).joined(separator: "\n")
    }
}
