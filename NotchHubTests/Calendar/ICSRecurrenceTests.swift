import Foundation
import Testing
@testable import NotchHub

struct ICSRecurrenceTests {
    private typealias F = CalendarICSFixtures

    private func series(_ properties: [String], extra: [String] = []) -> [CalendarEvent] {
        F.expand(F.calendar(F.event(["UID:series", "SUMMARY:Series"] + properties) + extra))
    }

    private func days(_ events: [CalendarEvent]) -> [Int] {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        return events.map { utc.component(.day, from: $0.start) }
    }

    @Test func dailyWithCount() {
        let events = series(["DTSTART:20260302T090000Z", "DTEND:20260302T093000Z", "RRULE:FREQ=DAILY;COUNT=5"])
        #expect(days(events) == [2, 3, 4, 5, 6])
        #expect(events.allSatisfy { $0.end.timeIntervalSince($0.start) == 1800 })
    }

    @Test func dailyWithIntervalSkipsAheadToWindow() {
        let events = series(["DTSTART:20200101T090000Z", "RRULE:FREQ=DAILY;INTERVAL=10"])
        // 2020-01-01 + 10n days: the March 2026 hits are the 10th, 20th and 30th.
        #expect(days(events) == [10, 20, 30])
    }

    @Test func weeklyByDayUntil() {
        let events = series(["DTSTART:20260302T090000Z", "RRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20260318T235959Z"])
        #expect(days(events) == [2, 4, 9, 11, 16, 18])
    }

    @Test func weeklyWithIntervalTwo() {
        let events = series(["DTSTART:20260303T090000Z", "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TU"])
        #expect(days(events) == [3, 17, 31])
    }

    @Test func weeklyKeepsWallClockAcrossDST() {
        let events = series([
            "DTSTART;TZID=W. Europe Standard Time:20260323T090000",
            "RRULE:FREQ=WEEKLY;COUNT=2",
        ])
        #expect(events.map(\.start) == [F.utc("2026-03-23T08:00:00Z"), F.utc("2026-03-30T07:00:00Z")])
    }

    @Test func monthlyByMonthDayIncludingNegative() {
        let window = DateInterval(start: F.utc("2026-01-01T00:00:00Z"), end: F.utc("2026-04-01T00:00:00Z"))
        let text = F.calendar(F.event([
            "UID:m", "SUMMARY:M", "DTSTART:20260115T090000Z", "RRULE:FREQ=MONTHLY;BYMONTHDAY=15,-1;COUNT=4",
        ]))
        let starts = F.expand(text, window: window).map(\.start)
        #expect(starts == [
            F.utc("2026-01-15T09:00:00Z"), F.utc("2026-01-31T09:00:00Z"),
            F.utc("2026-02-15T09:00:00Z"), F.utc("2026-02-28T09:00:00Z"),
        ])
    }

    @Test func monthlyByOrdinalWeekday() {
        let window = DateInterval(start: F.utc("2026-03-01T00:00:00Z"), end: F.utc("2026-05-01T00:00:00Z"))
        let text = F.calendar(F.event([
            "UID:m", "SUMMARY:M", "DTSTART:20260210T090000Z", "RRULE:FREQ=MONTHLY;BYDAY=2TU",
        ]))
        #expect(F.expand(text, window: window).map(\.start) == [F.utc("2026-03-10T09:00:00Z"), F.utc("2026-04-14T09:00:00Z")])
    }

    @Test func monthlyLastWeekdayWithSetPosition() {
        let events = series(["DTSTART:20260130T090000Z", "RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1"])
        #expect(days(events) == [31])
    }

    @Test func yearlyByMonthAndDay() {
        let events = series(["DTSTART:20200310T090000Z", "RRULE:FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=10"])
        #expect(events.map(\.start) == [F.utc("2026-03-10T09:00:00Z")])
    }

    @Test func yearlyUntilBeforeWindowProducesNothing() {
        #expect(series(["DTSTART:20200310T090000Z", "RRULE:FREQ=YEARLY;UNTIL=20250101T000000Z"]).isEmpty)
    }

    @Test func exdateRemovesOccurrences() {
        let events = series([
            "DTSTART;TZID=Turkey Standard Time:20260302T120000",
            "RRULE:FREQ=DAILY;COUNT=4",
            "EXDATE;TZID=Turkey Standard Time:20260303T120000,20260305T120000",
        ])
        #expect(days(events) == [2, 4])
    }

    @Test func recurrenceIDOverridesAndCancelsOccurrences() {
        let overrides = F.event([
            "UID:series",
            "RECURRENCE-ID:20260303T090000Z",
            "SUMMARY:Moved",
            "DTSTART:20260303T150000Z",
            "DTEND:20260303T153000Z",
        ]) + F.event([
            "UID:series",
            "RECURRENCE-ID:20260304T090000Z",
            "STATUS:CANCELLED",
            "DTSTART:20260304T090000Z",
        ])
        let events = series(
            ["DTSTART:20260302T090000Z", "DTEND:20260302T093000Z", "RRULE:FREQ=DAILY;COUNT=4", "LOCATION:Room 1"],
            extra: overrides
        )

        #expect(events.map(\.title) == ["Series", "Moved", "Series"])
        #expect(events[1].start == F.utc("2026-03-03T15:00:00Z"))
        #expect(events[1].location == "Room 1")
        #expect(days(events) == [2, 3, 5])
    }

    @Test func allDayRecurrenceStaysOnLocalMidnight() throws {
        let events = series(["DTSTART;VALUE=DATE:20260302", "DTEND;VALUE=DATE:20260303", "RRULE:FREQ=WEEKLY;COUNT=2"])
        let first = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 2)))
        let second = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 9)))
        #expect(events.map(\.start) == [first, second])
        #expect(events.allSatisfy { $0.isAllDay })
    }

    @Test func parsesRuleFields() {
        let rule = ICSValueParser.recurrenceRule(
            "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,-1FR;COUNT=3;WKST=SU",
            tzid: nil,
            customOffsets: [:]
        )
        #expect(rule?.frequency == .weekly)
        #expect(rule?.interval == 2)
        #expect(rule?.count == 3)
        #expect(rule?.weekStart == 1)
        #expect(rule?.byDay == [ICSWeekdayRule(weekday: 2, ordinal: nil), ICSWeekdayRule(weekday: 6, ordinal: -1)])
    }
}
