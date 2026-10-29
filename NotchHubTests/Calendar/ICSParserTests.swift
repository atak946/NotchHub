import Foundation
import Testing
@testable import NotchHub

struct ICSParserTests {
    private typealias F = CalendarICSFixtures

    @Test func unfoldsFoldedLinesAndUnescapesText() {
        let text = F.calendar(F.event([
            "UID:fold-1",
            "SUMMARY:Sync\\, planning \\; review",
            "DESCRIPTION:Join Zoom Meeting\\nhttps://us02web.zoom.us/j/8123",
            " 4567890?pwd=abc",
            "\tdef",
            "DTSTART:20260310T090000Z",
            "DTEND:20260310T093000Z",
        ]))

        let event = ICSParser.parse(text).events.first

        #expect(event?.summary == "Sync, planning ; review")
        #expect(event?.description == "Join Zoom Meeting\nhttps://us02web.zoom.us/j/81234567890?pwd=abcdef")
        #expect(ICSParser.parse(text).name == "Work")
    }

    @Test func parsesQuotedParametersContainingColons() {
        let line = ICSContentLineReader.parse(#"DTSTART;TZID="(UTC+03:00) Istanbul":20260310T090000"#)
        #expect(line?.name == "DTSTART")
        #expect(line?.parameter("tzid") == "(UTC+03:00) Istanbul")
        #expect(line?.value == "20260310T090000")
    }

    @Test(arguments: [
        ("Turkey Standard Time", "2026-03-10T06:00:00Z"),
        ("W. Europe Standard Time", "2026-03-10T08:00:00Z"),
        ("Eastern Standard Time", "2026-03-10T13:00:00Z"),
        ("Europe/Istanbul", "2026-03-10T06:00:00Z"),
        ("(UTC+03:00) Istanbul", "2026-03-10T06:00:00Z"),
        ("/mozilla.org/20050126_1/Europe/Berlin", "2026-03-10T08:00:00Z"),
    ])
    func resolvesTimeZones(tzid: String, expected: String) {
        let text = F.calendar(F.event([
            "UID:tz",
            "SUMMARY:TZ",
            "DTSTART;TZID=\"\(tzid)\":20260310T090000",
            "DTEND;TZID=\"\(tzid)\":20260310T100000",
        ]))

        let event = ICSParser.parse(text).events.first

        #expect(event?.start?.date == F.utc(expected))
        #expect(event?.end?.date == F.utc(expected).addingTimeInterval(3600))
    }

    @Test func usesCustomVTimeZoneOffsetForUnknownTZID() {
        let text = F.calendar([
            "BEGIN:VTIMEZONE",
            "TZID:Customized Time Zone",
            "BEGIN:STANDARD",
            "DTSTART:16010101T000000",
            "TZOFFSETFROM:+0300",
            "TZOFFSETTO:+0300",
            "END:STANDARD",
            "END:VTIMEZONE",
        ] + F.event([
            "UID:custom",
            "SUMMARY:Custom",
            "DTSTART;TZID=Customized Time Zone:20260310T090000",
        ]))

        #expect(ICSParser.parse(text).events.first?.start?.date == F.utc("2026-03-10T06:00:00Z"))
    }

    @Test func parsesUTCAndAllDayDates() throws {
        let text = F.calendar(F.event([
            "UID:allday",
            "SUMMARY:Holiday",
            "DTSTART;VALUE=DATE:20260310",
            "DTEND;VALUE=DATE:20260311",
        ]) + F.event([
            "UID:utc",
            "SUMMARY:UTC",
            "DTSTART:20260310T090000Z",
            "DURATION:PT1H30M",
        ]))

        let events = F.expand(text)
        let allDay = try #require(events.first { $0.title == "Holiday" })
        let utc = try #require(events.first { $0.title == "UTC" })

        let expectedStart = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 10)))
        #expect(allDay.isAllDay)
        #expect(allDay.start == expectedStart)
        #expect(allDay.end == Calendar.current.date(byAdding: .day, value: 1, to: expectedStart))
        #expect(utc.start == F.utc("2026-03-10T09:00:00Z"))
        #expect(utc.end == F.utc("2026-03-10T10:30:00Z"))
    }

    @Test func skipsCancelledEvents() {
        let text = F.calendar(F.event([
            "UID:gone",
            "SUMMARY:Cancelled meeting",
            "STATUS:CANCELLED",
            "DTSTART:20260310T090000Z",
        ]) + F.event([
            "UID:kept",
            "SUMMARY:Kept",
            "STATUS:CONFIRMED",
            "DTSTART:20260310T100000Z",
        ]))

        #expect(F.expand(text).map(\.title) == ["Kept"])
        #expect(ICSParser.parse(text).eventCount == 1)
    }

    @Test func detectsTeamsZoomAndLocationLinks() {
        let text = F.calendar(F.event([
            "UID:teams",
            "SUMMARY:Teams",
            "DTSTART:20260310T090000Z",
            "X-MICROSOFT-SKYPETEAMSMEETINGURL:https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0",
            "DESCRIPTION:Agenda only",
        ]) + F.event([
            "UID:zoom-desc",
            "SUMMARY:Zoom in body",
            "DTSTART:20260310T100000Z",
            "DESCRIPTION:Hi\\nJoin: https://us02web.zoom.us/j/81234567890?pwd=abc\\nThanks",
        ]) + F.event([
            "UID:zoom-loc",
            "SUMMARY:Zoom in location",
            "DTSTART:20260310T110000Z",
            "LOCATION:us06web.zoom.us/j/555666777",
        ]) + F.event([
            "UID:conf",
            "SUMMARY:Conf link",
            "DTSTART:20260310T120000Z",
            "X-MICROSOFT-ONLINEMEETINGCONFLINK:conf:sip:jane@contoso.com\\;gruu\\;opaque=app:conf:focus:id:ABC",
            "LOCATION:Microsoft Teams Meeting",
            "DESCRIPTION:https://teams.microsoft.com/l/meetup-join/19%3ameeting_def%40thread.v2/0",
        ]))

        let providers = F.expand(text).map { $0.meetingLink?.provider }

        #expect(providers == [.teams, .zoom, .zoom, .teams])
    }

    @Test func ignoresComponentsNestedInEvents() {
        let text = F.calendar(F.event([
            "UID:alarm",
            "SUMMARY:With alarm",
            "DTSTART:20260310T090000Z",
            "BEGIN:VALARM",
            "DESCRIPTION:Reminder",
            "TRIGGER:-PT15M",
            "END:VALARM",
        ]))

        let event = ICSParser.parse(text).events.first
        #expect(event?.description == nil)
        #expect(event?.summary == "With alarm")
    }

    @Test(arguments: [
        ("PT1H30M", 5400.0),
        ("P1D", 86_400.0),
        ("P1W", 604_800.0),
        ("-PT15M", -900.0),
        ("P1DT2H", 93_600.0),
    ])
    func parsesDurations(text: String, seconds: Double) {
        #expect(ICSValueParser.duration(text) == seconds)
    }
}
