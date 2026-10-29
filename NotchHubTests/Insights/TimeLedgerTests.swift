import Foundation
import Testing
@testable import NotchHub

struct TimeLedgerTests {
    private let calendar = InsightsTestDates.calendar

    @Test func dayKeyUsesCalendarTimeZone() {
        #expect(TimeLedgerDay.key(for: InsightsTestDates.date(23, 59), calendar: calendar) == "2026-10-28")
        #expect(TimeLedgerDay.key(for: InsightsTestDates.date(2026, 1, 2, 0, 0), calendar: calendar) == "2026-01-02")
    }

    @Test func splitWithinOneDay() {
        let credits = TimeLedgerDay.split(
            from: InsightsTestDates.date(10, 0), to: InsightsTestDates.date(10, 0, 15), calendar: calendar
        )
        #expect(credits == [DayCredit(day: "2026-10-28", seconds: 15)])
    }

    @Test func splitAcrossMidnight() {
        let credits = TimeLedgerDay.split(
            from: InsightsTestDates.date(23, 59, 50), to: InsightsTestDates.date(2026, 10, 29, 0, 0, 20), calendar: calendar
        )
        #expect(credits == [DayCredit(day: "2026-10-28", seconds: 10), DayCredit(day: "2026-10-29", seconds: 20)])
    }

    @Test func emptyOrReversedIntervalsCreditNothing() {
        let now = InsightsTestDates.date(12)
        #expect(TimeLedgerDay.split(from: now, to: now, calendar: calendar).isEmpty)
        #expect(TimeLedgerDay.split(from: now, to: now.addingTimeInterval(-5), calendar: calendar).isEmpty)
    }

    @Test func addingAggregatesSameBucketWithoutMutatingOriginal() {
        let base = TimeLedger.empty
        let once = base.adding(seconds: 15, client: "Northwind", appBundleID: "com.a", day: "2026-10-28")
        let twice = once.adding(seconds: 30, client: "Northwind", appBundleID: "com.a", day: "2026-10-28")
        #expect(base.entries.isEmpty)
        #expect(once.entries.count == 1)
        #expect(twice.entries == [TimeLedgerEntry(day: "2026-10-28", client: "Northwind", appBundleID: "com.a", seconds: 45)])
    }

    @Test func separateBucketsPerDayClientAndApp() {
        let ledger = TimeLedger.empty
            .adding(seconds: 60, client: "Northwind", appBundleID: "com.a", day: "2026-10-28")
            .adding(seconds: 60, client: "Northwind", appBundleID: "com.b", day: "2026-10-28")
            .adding(seconds: 60, client: "Globex", appBundleID: "com.a", day: "2026-10-28")
            .adding(seconds: 60, client: "Northwind", appBundleID: "com.a", day: "2026-10-29")
            .adding(seconds: 0, client: "Northwind", appBundleID: nil, day: "2026-10-29")
        #expect(ledger.entries.count == 4)
        #expect(ledger.totalSeconds(on: "2026-10-28") == 180)
        #expect(ledger.clientTotals(on: "2026-10-28") == [
            ClientTotal(client: "Northwind", seconds: 120), ClientTotal(client: "Globex", seconds: 60),
        ])
    }

    @Test func clientTotalsTieBreakAlphabetically() {
        let ledger = TimeLedger.empty
            .adding(seconds: 60, client: "B", appBundleID: nil, day: "d")
            .adding(seconds: 60, client: "A", appBundleID: nil, day: "d")
        #expect(ledger.clientTotals(on: "d").map(\.client) == ["A", "B"])
        #expect(ledger.entries.allSatisfy { $0.appBundleID == TimeLedger.unknownApp })
    }

    @Test func weekKeysStartOnMonday() {
        let keys = TimeLedgerDay.weekKeys(containing: InsightsTestDates.date(12), calendar: calendar)
        #expect(keys.first == "2026-10-26")
        #expect(keys.last == "2026-11-01")
        #expect(keys.count == 7)
    }
}
