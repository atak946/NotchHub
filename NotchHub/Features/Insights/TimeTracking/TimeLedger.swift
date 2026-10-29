import Foundation

/// Aggregated tracked time for one day/client/app. No window titles are ever stored.
struct TimeLedgerEntry: Codable, Equatable, Sendable {
    let day: String
    let client: String
    let appBundleID: String
    let seconds: Int
}

struct ClientTotal: Identifiable, Equatable, Sendable {
    let client: String
    let seconds: Int

    var id: String { client }
}

/// Immutable aggregate of tracked time, persisted as JSON.
struct TimeLedger: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let unknownApp = "unknown"

    let version: Int
    let entries: [TimeLedgerEntry]

    init(entries: [TimeLedgerEntry] = []) {
        version = Self.currentVersion
        self.entries = entries
    }

    static let empty = TimeLedger()

    func adding(seconds: Int, client: String, appBundleID: String?, day: String) -> TimeLedger {
        guard seconds > 0 else { return self }
        let app = appBundleID ?? Self.unknownApp
        let isSameBucket = { (entry: TimeLedgerEntry) in
            entry.day == day && entry.client == client && entry.appBundleID == app
        }
        let existing = entries.first(where: isSameBucket)?.seconds ?? 0
        let updated = TimeLedgerEntry(day: day, client: client, appBundleID: app, seconds: existing + seconds)
        return TimeLedger(entries: entries.filter { !isSameBucket($0) } + [updated])
    }

    func adding(_ credits: [DayCredit], client: String, appBundleID: String?) -> TimeLedger {
        credits.reduce(self) { $0.adding(seconds: $1.seconds, client: client, appBundleID: appBundleID, day: $1.day) }
    }

    func entries(on days: Set<String>) -> [TimeLedgerEntry] {
        entries.filter { days.contains($0.day) }
    }

    func totalSeconds(on day: String) -> Int {
        entries.lazy.filter { $0.day == day }.reduce(0) { $0 + $1.seconds }
    }

    /// Per-client totals for one day, largest first.
    func clientTotals(on day: String) -> [ClientTotal] {
        let grouped = Dictionary(grouping: entries.filter { $0.day == day }, by: \.client)
        return grouped
            .map { ClientTotal(client: $0.key, seconds: $0.value.reduce(0) { $0 + $1.seconds }) }
            .sorted { ($0.seconds, $1.client) > ($1.seconds, $0.client) }
    }
}

/// Seconds credited to one calendar day.
struct DayCredit: Equatable, Sendable {
    let day: String
    let seconds: Int
}

enum TimeLedgerDay {
    /// Stable "yyyy-MM-dd" key in `calendar`'s time zone (no DateFormatter, locale independent).
    static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Splits `[start, end)` at local midnights so time is booked to the day it happened.
    static func split(from start: Date, to end: Date, calendar: Calendar) -> [DayCredit] {
        guard end > start else { return [] }
        var credits: [DayCredit] = []
        var cursor = start
        while cursor < end {
            let nextMidnight = calendar.nextDate(
                after: cursor, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime
            ) ?? end
            let pieceEnd = min(nextMidnight, end)
            let seconds = Int(pieceEnd.timeIntervalSince(cursor).rounded())
            if seconds > 0 {
                credits.append(DayCredit(day: key(for: cursor, calendar: calendar), seconds: seconds))
            }
            cursor = pieceEnd
        }
        return credits
    }

    /// Day keys of the calendar week containing `date` (respects `calendar.firstWeekday`).
    static func weekKeys(containing date: Date, calendar: Calendar) -> [String] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return [key(for: date, calendar: calendar)]
        }
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: week.start).map { key(for: $0, calendar: calendar) }
        }
    }
}
