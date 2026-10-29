import Foundation
import Testing
@testable import NotchHub

@MainActor
struct ICSFeedSourceTests {
    private typealias F = CalendarICSFixtures
    nonisolated private static let feedURL = "webcal://outlook.office365.com/owa/calendar/abc/def/calendar.ics"

    nonisolated private static let body = F.calendar(F.event([
        "UID:one", "SUMMARY:Standup", "DTSTART:20260310T090000Z", "DTEND:20260310T091500Z",
        "LOCATION:https://zoom.us/j/123456789",
    ]) + F.event([
        "UID:two", "SUMMARY:Review", "DTSTART:20260310T130000Z", "DTEND:20260310T140000Z",
    ]))

    private func makeSource(
        http: CalendarTestHTTPClient,
        secrets: CalendarTestSecretStore = CalendarTestSecretStore(),
        defaults: UserDefaults = CalendarFixtures.makeDefaults()
    ) -> ICSFeedSource {
        ICSFeedSource(defaults: defaults, secrets: secrets, http: http, sleep: { _ in })
    }

    private func allEvents(_ source: ICSFeedSource) throws -> [CalendarEvent] {
        try source.events(from: F.march.start, to: F.march.end).sorted { $0.start < $1.start }
    }

    @Test func storesFeedURLInSecretStoreOnly() throws {
        let secrets = CalendarTestSecretStore()
        let defaults = CalendarFixtures.makeDefaults()
        let source = makeSource(http: CalendarTestHTTPClient(sequence: [.text(Self.body)]), secrets: secrets, defaults: defaults)

        let feed = try source.addFeed(name: " Work ", urlString: Self.feedURL)

        #expect(feed.name == "Work")
        #expect(feed.kind == .outlook)
        #expect(secrets.all.values.contains("https://outlook.office365.com/owa/calendar/abc/def/calendar.ics"))
        let stored = defaults.data(forKey: ICSFeedStore.key).map { String(decoding: $0, as: UTF8.self) } ?? ""
        #expect(stored.contains(feed.id))
        #expect(!stored.contains("outlook.office365.com"))
        #expect(source.authorization == .authorized)

        let reloaded = makeSource(http: CalendarTestHTTPClient(sequence: [.text(Self.body)]), secrets: secrets, defaults: defaults)
        #expect(reloaded.feeds == [feed])
    }

    @Test func rejectsInvalidAndInsecureLinks() {
        let source = makeSource(http: CalendarTestHTTPClient(sequence: [.text(Self.body)]))
        #expect(throws: ICSFeedURL.ValidationError.insecure) { try source.addFeed(name: "", urlString: "http://example.com/a.ics") }
        #expect(throws: ICSFeedURL.ValidationError.invalid) { try source.addFeed(name: "", urlString: "not a url") }
        #expect(throws: ICSFeedURL.ValidationError.invalid) { try source.addFeed(name: "", urlString: "ftp://example.com/a.ics") }
        #expect(source.feeds.isEmpty)
    }

    @Test func classifiesFeedHosts() throws {
        #expect(ICSFeedURL.accountKind(for: try ICSFeedURL.normalized("https://outlook.live.com/owa/calendar/x/calendar.ics")) == .outlook)
        #expect(ICSFeedURL.accountKind(for: try ICSFeedURL.normalized("webcal://calendar.google.com/x/basic.ics")) == .other)
    }

    @Test func syncsEventsAndExposesAccountAndCalendar() async throws {
        let source = makeSource(http: CalendarTestHTTPClient(sequence: [.text(Self.body, headers: ["ETag": "\"v1\""])]))
        let feed = try source.addFeed(name: "Work", urlString: Self.feedURL)

        await source.refreshNow()
        let events = try allEvents(source)

        #expect(events.map(\.title) == ["Standup", "Review"])
        #expect(events.first?.meetingLink?.provider == .zoom)
        #expect(events.first?.account == feed.account)
        #expect(events.first?.calendarID == feed.calendarID)
        #expect(source.accounts() == [feed.account])
        #expect(source.calendars().map(\.id) == [feed.calendarID])
        #expect(source.feedStatus[feed.id]?.eventCount == 2)
    }

    @Test func sendsConditionalHeadersAndKeepsEventsOn304() async throws {
        let http = CalendarTestHTTPClient { request in
            if request.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"" {
                return .text("", status: 304)
            }
            return .text(Self.body, headers: ["ETag": "\"v1\"", "Last-Modified": "Tue, 10 Mar 2026 08:00:00 GMT"])
        }
        let source = makeSource(http: http)
        try source.addFeed(name: "Work", urlString: Self.feedURL)

        await source.refreshNow()
        await source.refreshNow()

        let last = try #require(http.requests.last)
        #expect(last.url?.scheme == "https")
        #expect(last.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(last.value(forHTTPHeaderField: "If-Modified-Since") == "Tue, 10 Mar 2026 08:00:00 GMT")
        #expect(try allEvents(source).count == 2)
    }

    @Test func failingFeedThrowsUntilFirstSuccessfulSync() async throws {
        let source = makeSource(http: CalendarTestHTTPClient(sequence: [.text("oops", status: 500)]))
        let feed = try source.addFeed(name: "Broken", urlString: Self.feedURL)

        await source.refreshNow()

        #expect(source.feedStatus[feed.id]?.errorMessage != nil)
        #expect(source.statusMessage?.contains("Broken") == true)
        #expect(throws: ICSFeedSource.FeedError.self) { try allEvents(source) }
    }

    @Test func rejectsNonCalendarResponses() async throws {
        let source = makeSource(http: CalendarTestHTTPClient(sequence: [.text("<html>Sign in</html>")]))
        let feed = try source.addFeed(name: "Login page", urlString: Self.feedURL)

        await source.refreshNow()

        #expect(source.feedStatus[feed.id]?.errorMessage == ICSFeedSource.FeedError.notACalendar.localizedDescription)
    }

    @Test func testFeedReportsEventCount() async {
        let source = makeSource(http: CalendarTestHTTPClient(sequence: [.text(Self.body)]))

        let result = await source.testFeed(urlString: Self.feedURL)

        #expect(result == .success(eventCount: 2, calendarName: "Work"))
        #expect(result.message == "Found 2 events")
        #expect(source.feeds.isEmpty)
    }

    @Test func renameAndRemoveFeed() throws {
        let secrets = CalendarTestSecretStore()
        let source = makeSource(http: CalendarTestHTTPClient(sequence: [.text(Self.body)]), secrets: secrets)
        let feed = try source.addFeed(name: "Work", urlString: Self.feedURL)

        source.renameFeed(id: feed.id, to: "Office")
        source.renameFeed(id: feed.id, to: "   ")
        #expect(source.feeds.first?.name == "Office")
        #expect(source.calendars().first?.title == "Office")

        source.removeFeed(id: feed.id)
        #expect(source.feeds.isEmpty)
        #expect(secrets.all.isEmpty)
        #expect(source.authorization == .notDetermined)
    }
}
