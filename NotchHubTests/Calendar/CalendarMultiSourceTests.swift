import Foundation
import Testing
@testable import NotchHub

private struct CalendarMultiSourceTestError: Error, LocalizedError {
    var errorDescription: String? { "Feed offline" }
}

@MainActor
struct CalendarMultiSourceTests {
    private typealias F = CalendarFixtures

    private func makeService(_ sources: [FakeCalendarSource], at date: Date) -> CalendarService {
        let clock = CalendarTestClock(date)
        return CalendarService(sources: sources, defaults: F.makeDefaults(), now: { clock.now })
    }

    private func source(_ id: String, events: [CalendarEvent], authorization: CalendarAuthorization = .authorized) -> FakeCalendarSource {
        let source = FakeCalendarSource(authorization: authorization)
        source.sourceID = id
        source.sourceName = id
        source.storedEvents = events
        return source
    }

    @Test func aggregatesEventsAccountsAndCalendarsFromAllSources() {
        let eventKit = source("eventkit", events: [F.event("icloud", start: F.date(hour: 10), calendarID: "c-icloud", account: F.iCloud)])
        eventKit.storedAccounts = [F.iCloud]
        eventKit.storedCalendars = [CalendarInfo(id: "c-icloud", title: "Home", color: .fallback, accountID: F.iCloud.id)]
        let ics = source("ics", events: [F.event("outlook", start: F.date(hour: 11), calendarID: "c-ics", account: F.outlook)])
        ics.storedAccounts = [F.outlook]
        ics.storedCalendars = [CalendarInfo(id: "c-ics", title: "Work", color: .fallback, accountID: F.outlook.id)]
        let service = makeService([eventKit, ics], at: F.date(hour: 9))

        service.refresh()

        #expect(service.todayEvents.map(\.id) == ["icloud", "outlook"])
        #expect(service.accounts == [F.iCloud, F.outlook])
        #expect(service.calendars.map(\.id) == ["c-icloud", "c-ics"])

        service.setCalendar("c-ics", visible: false)
        #expect(service.todayEvents.map(\.id) == ["icloud"])
    }

    @Test func failingSourceDoesNotHideOthers() {
        let healthy = source("eventkit", events: [F.event("ok", start: F.date(hour: 10))])
        let broken = source("ics", events: [F.event("never", start: F.date(hour: 11))])
        broken.failure = CalendarMultiSourceTestError()
        let service = makeService([healthy, broken], at: F.date(hour: 9))

        service.refresh()

        #expect(service.nextEvent?.id == "ok")
        #expect(service.todayEvents.map(\.id) == ["ok"])
        #expect(service.sourceDiagnostics.map(\.summary) == ["Bugün 1 etkinlik", "Bugün 0 etkinlik · Feed offline"])
    }

    @Test func remoteSourceWorksWhenEventKitIsDenied() {
        let eventKit = source("eventkit", events: [], authorization: .denied)
        let graph = source("microsoft365", events: [F.event("graph", start: F.date(hour: 10), link: F.link(.teams))])
        let service = makeService([eventKit, graph], at: F.date(hour: 9))

        service.refresh()

        #expect(service.authorization == .authorized)
        #expect(service.primaryAuthorization == .denied)
        #expect(service.nextEvent?.id == "graph")
        #expect(service.sourceDiagnostics.first?.isActive == false)
        #expect(service.sourceDiagnostics.first?.summary == "Erişim yok")
    }

    @Test func authorizationFallsBackToPrimaryWhenNothingIsConnected() {
        let eventKit = source("eventkit", events: [], authorization: .denied)
        let ics = source("ics", events: [], authorization: .notDetermined)
        let service = makeService([eventKit, ics], at: F.date(hour: 9))

        service.refresh()

        #expect(service.authorization == .denied)
        #expect(service.sourceDiagnostics.map(\.summary) == ["Erişim yok", "Bağlı değil"])
    }

    @Test func dedupesSameMeetingFromTwoSourcesPreferringRicherOne() {
        let plain = CalendarEvent(id: "ek", title: "Weekly Sync", start: F.date(hour: 10), end: F.date(hour: 10, minute: 30))
        let rich = CalendarEvent(
            id: "graph",
            title: "weekly  sync",
            start: F.date(hour: 10, second: 40),
            end: F.date(hour: 10, minute: 30),
            location: "Zoom",
            meetingLink: F.link(.zoom),
            calendarTitle: "Outlook Calendar"
        )
        let service = makeService([source("eventkit", events: [plain]), source("microsoft365", events: [rich])], at: F.date(hour: 9))

        service.refresh()

        #expect(service.todayEvents.map(\.id) == ["graph"])
        #expect(service.sourceDiagnostics.map(\.eventsToday) == [1, 1])
    }

    @Test func dedupeKeepsPrimarySourceOnTies() {
        let first = F.event("ek", start: F.date(hour: 10), link: F.link(.teams))
        let second = F.event("ics", start: F.date(hour: 10), link: F.link(.teams))
        let result = CalendarEventDeduplicator.deduplicate([first, CalendarEvent(
            id: "ics", title: "ek", start: second.start, end: second.end, meetingLink: second.meetingLink,
            calendarID: second.calendarID, calendarTitle: second.calendarTitle, account: second.account
        )])

        #expect(result.map(\.id) == ["ek"])
    }

    @Test func dedupeKeepsDistinctMeetings() {
        let zoomA = CalendarEvent(
            id: "a", title: "1:1", start: F.date(hour: 10), end: F.date(hour: 10, minute: 30),
            meetingLink: MeetingLink(provider: .zoom, url: URL(fileURLWithPath: "/a"))
        )
        let zoomB = CalendarEvent(
            id: "b", title: "1:1", start: F.date(hour: 10), end: F.date(hour: 10, minute: 30),
            meetingLink: MeetingLink(provider: .zoom, url: URL(fileURLWithPath: "/b"))
        )
        let later = CalendarEvent(id: "c", title: "1:1", start: F.date(hour: 10, minute: 2), end: F.date(hour: 10, minute: 30))
        let otherTitle = CalendarEvent(id: "d", title: "Lunch", start: F.date(hour: 10), end: F.date(hour: 11))

        let result = CalendarEventDeduplicator.deduplicate([zoomA, zoomB, later, otherTitle])

        #expect(Set(result.map(\.id)) == ["a", "b", "c", "d"])
    }

    @Test func dedupeIgnoresZoomPasswordDifferences() throws {
        let withPassword = try #require(URL(string: "https://us02web.zoom.us/j/123?pwd=abc"))
        let without = try #require(URL(string: "https://us02web.zoom.us/j/123"))
        let lhs = CalendarEvent(id: "a", title: "Demo", start: F.date(hour: 10), end: F.date(hour: 11), meetingLink: MeetingLink(provider: .zoom, url: withPassword))
        let rhs = CalendarEvent(id: "b", title: "Demo", start: F.date(hour: 10), end: F.date(hour: 11), meetingLink: MeetingLink(provider: .zoom, url: without))

        #expect(CalendarEventDeduplicator.isDuplicate(lhs, rhs))
    }

    @Test func startAndStopObserveEverySource() {
        let first = source("a", events: [])
        let second = source("b", events: [])
        let service = makeService([first, second], at: F.date(hour: 9))

        service.start()
        #expect(first.changeHandler != nil && second.changeHandler != nil)
        second.storedEvents = [F.event("pushed", start: F.date(hour: 12))]
        second.simulateStoreChange()
        #expect(service.nextEvent?.id == "pushed")

        service.stop()
        #expect(first.changeHandler == nil && second.changeHandler == nil)
    }

    @Test func requestAccessAsksEveryUndecidedSource() async {
        let eventKit = source("eventkit", events: [F.event("a", start: F.date(hour: 10))], authorization: .notDetermined)
        let other = source("other", events: [], authorization: .notDetermined)
        other.grantOnRequest = false
        let service = makeService([eventKit, other], at: F.date(hour: 9))

        service.requestAccess()
        for _ in 0..<50 where service.nextEvent == nil {
            await Task.yield()
        }

        #expect(eventKit.requestCount == 1)
        #expect(other.requestCount == 1)
        #expect(service.authorization == .authorized)
    }

    @Test func endToEndWithICSFeedSource() async throws {
        let body = CalendarICSFixtures.calendar(CalendarICSFixtures.event([
            "UID:x", "SUMMARY:Feed meeting", "DTSTART:20260310T100000Z", "DTEND:20260310T110000Z",
            "X-MICROSOFT-SKYPETEAMSMEETINGURL:https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0",
        ]))
        let feeds = ICSFeedSource(
            defaults: F.makeDefaults(),
            secrets: CalendarTestSecretStore(),
            http: CalendarTestHTTPClient(sequence: [.text(body)]),
            sleep: { _ in }
        )
        try feeds.addFeed(name: "Work", urlString: "https://outlook.office365.com/owa/calendar/a/b/calendar.ics")
        await feeds.refreshNow()
        let eventKit = FakeCalendarSource(authorization: .denied)
        let clock = CalendarTestClock(CalendarICSFixtures.utc("2026-03-10T08:00:00Z"))
        let service = CalendarService(sources: [eventKit, feeds], defaults: F.makeDefaults(), now: { clock.now })

        service.refresh()

        #expect(service.nextEvent?.title == "Feed meeting")
        #expect(service.nextEvent?.meetingLink?.provider == .teams)
        #expect(service.nextEvent?.account.kind == .outlook)
        #expect(service.icsFeedSource === feeds)
        #expect(service.microsoftSource == nil)
        #expect(service.accounts.map(\.kind) == [.outlook])
    }
}
