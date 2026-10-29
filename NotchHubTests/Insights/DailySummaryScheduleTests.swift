import Foundation
import Testing
@testable import NotchHub

struct DailySummaryScheduleTests {
    private let calendar = InsightsTestDates.calendar
    private let schedule = DailySummarySchedule()

    @Test func defaultsTo1800OnWeekdays() {
        #expect(schedule.hour == 18 && schedule.minute == 0 && schedule.weekdaysOnly)
        #expect(schedule.fireDate(onDayOf: InsightsTestDates.date(9), calendar: calendar) == InsightsTestDates.date(18))
    }

    @Test func skipsWeekends() {
        // 2026-10-31 is a Saturday.
        #expect(schedule.fireDate(onDayOf: InsightsTestDates.date(2026, 10, 31, 9), calendar: calendar) == nil)
        let friday = DailySummarySchedule().nextFireDate(after: InsightsTestDates.date(2026, 10, 30, 19), calendar: calendar)
        #expect(friday == InsightsTestDates.date(2026, 11, 2, 18))
    }

    @Test func nextFireDateIsStrictlyAfter() {
        #expect(schedule.nextFireDate(after: InsightsTestDates.date(17, 59), calendar: calendar) == InsightsTestDates.date(18))
        #expect(schedule.nextFireDate(after: InsightsTestDates.date(18), calendar: calendar) == InsightsTestDates.date(2026, 10, 29, 18))
    }

    @Test func shouldFireOncePerDayInsideWindow() {
        #expect(!schedule.shouldFire(now: InsightsTestDates.date(17, 59), lastFiredDay: nil, calendar: calendar))
        #expect(schedule.shouldFire(now: InsightsTestDates.date(18, 0, 10), lastFiredDay: nil, calendar: calendar))
        #expect(schedule.shouldFire(now: InsightsTestDates.date(18), lastFiredDay: "2026-10-27", calendar: calendar))
        #expect(!schedule.shouldFire(now: InsightsTestDates.date(18, 5), lastFiredDay: "2026-10-28", calendar: calendar))
        #expect(!schedule.shouldFire(now: InsightsTestDates.date(21, 0), lastFiredDay: nil, calendar: calendar))
    }

    @Test func weekendsFireWhenNotWeekdaysOnly() {
        let everyDay = DailySummarySchedule(hour: 9, minute: 30, weekdaysOnly: false)
        #expect(everyDay.shouldFire(now: InsightsTestDates.date(2026, 10, 31, 9, 31), lastFiredDay: nil, calendar: calendar))
    }

    @Test func summaryFormatting() {
        let totals = [
            ClientTotal(client: "Northwind", seconds: 3 * 3600), ClientTotal(client: "Globex", seconds: 2 * 3600),
            ClientTotal(client: "Acme", seconds: 1500), ClientTotal(client: "Misc", seconds: 900),
        ]
        #expect(TimeSummaryFormatter.line(totalSeconds: 24_000, totals: totals)
            == "Bugün: 6sa 40dk takip edildi — Northwind 3sa, Globex 2sa, Acme 25dk…")
        #expect(TimeSummaryFormatter.clientLine(Array(totals.prefix(2))) == "Northwind 3sa, Globex 2sa")
        #expect(InsightsDurationFormatter.short(seconds: 59) == "0dk")
        #expect(InsightsDurationFormatter.short(seconds: 3660) == "1sa 1dk")
    }
}
