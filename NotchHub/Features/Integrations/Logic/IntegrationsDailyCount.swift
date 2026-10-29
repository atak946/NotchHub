import Foundation

/// Number of external alerts received on one local calendar day.
struct IntegrationsDailyCount: Equatable, Sendable {
    let day: Date
    let count: Int

    static func empty(at now: Date, calendar: Calendar) -> IntegrationsDailyCount {
        IntegrationsDailyCount(day: calendar.startOfDay(for: now), count: 0)
    }

    /// Count for `now`'s day; a stored count from an earlier day reads as zero.
    func count(at now: Date, calendar: Calendar) -> Int {
        calendar.isDate(day, inSameDayAs: now) ? count : 0
    }

    func incremented(at now: Date, calendar: Calendar) -> IntegrationsDailyCount {
        IntegrationsDailyCount(day: calendar.startOfDay(for: now), count: count(at: now, calendar: calendar) + 1)
    }
}
