import Foundation

/// Per-day distraction counter; resets automatically when the calendar day changes.
struct FocusDistractionLog: Codable, Equatable, Sendable {
    let day: String
    let count: Int

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func empty(on date: Date, calendar: Calendar) -> FocusDistractionLog {
        FocusDistractionLog(day: dayKey(for: date, calendar: calendar), count: 0)
    }

    func count(on date: Date, calendar: Calendar) -> Int {
        day == Self.dayKey(for: date, calendar: calendar) ? count : 0
    }

    func incremented(on date: Date, calendar: Calendar) -> FocusDistractionLog {
        let today = Self.dayKey(for: date, calendar: calendar)
        return FocusDistractionLog(day: today, count: (day == today ? count : 0) + 1)
    }
}
