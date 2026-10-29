import Foundation
import Testing
@testable import NotchHub

struct MicrosoftGraphTests {
    private typealias F = CalendarICSFixtures

    private static let context = CalendarSourceContext(
        idPrefix: "microsoft365",
        calendarID: "microsoft365.calendar",
        calendarTitle: "Outlook Calendar",
        color: .fallback,
        account: CalendarAccount(id: "microsoft365.account", title: "me@contoso.com", kind: .outlook)
    )

    private static let pageOne = """
    {
      "@odata.context": "https://graph.microsoft.com/v1.0/$metadata#users('x')/calendarView",
      "@odata.nextLink": "https://graph.microsoft.com/v1.0/me/calendarView?startDateTime=2026-03-10T00:00:00Z&$skip=2",
      "value": [
        {
          "@odata.etag": "W/\\"abc\\"",
          "id": "AAMk-1",
          "subject": "Teams sync",
          "bodyPreview": "Agenda",
          "isAllDay": false,
          "isCancelled": false,
          "webLink": "https://outlook.office365.com/owa/?itemid=1",
          "onlineMeetingUrl": null,
          "start": { "dateTime": "2026-03-10T09:00:00.0000000", "timeZone": "UTC" },
          "end": { "dateTime": "2026-03-10T09:30:00.0000000", "timeZone": "UTC" },
          "location": { "displayName": "Microsoft Teams Meeting" },
          "onlineMeeting": { "joinUrl": "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0" }
        },
        {
          "id": "AAMk-2",
          "subject": "Zoom with vendor",
          "bodyPreview": "",
          "isAllDay": false,
          "isCancelled": false,
          "start": { "dateTime": "2026-03-10T11:00:00.0000000", "timeZone": "UTC" },
          "end": { "dateTime": "2026-03-10T12:00:00.0000000", "timeZone": "UTC" },
          "location": { "displayName": "https://us02web.zoom.us/j/81234567890?pwd=abc" },
          "onlineMeeting": null
        }
      ]
    }
    """

    private static let pageTwo = """
    {
      "value": [
        {
          "id": "AAMk-3",
          "subject": "Cancelled",
          "isAllDay": false,
          "isCancelled": true,
          "start": { "dateTime": "2026-03-10T13:00:00.0000000", "timeZone": "UTC" },
          "end": { "dateTime": "2026-03-10T14:00:00.0000000", "timeZone": "UTC" }
        },
        {
          "id": "AAMk-4",
          "subject": "Offsite",
          "isAllDay": true,
          "start": { "dateTime": "2026-03-10T00:00:00.0000000", "timeZone": "UTC" },
          "end": { "dateTime": "2026-03-11T00:00:00.0000000", "timeZone": "UTC" },
          "body": { "contentType": "text", "content": "Dial in: https://zoom.us/j/999888777" }
        }
      ]
    }
    """

    @Test func decodesAndMapsCalendarViewPage() throws {
        let page = try JSONDecoder().decode(MicrosoftGraphEventPage.self, from: Data(Self.pageOne.utf8))
        let events = MicrosoftGraphEventMapper.events(from: page.value, context: Self.context)

        #expect(page.nextLink?.contains("$skip=2") == true)
        #expect(events.map(\.title) == ["Teams sync", "Zoom with vendor"])
        #expect(events[0].start == F.utc("2026-03-10T09:00:00Z"))
        #expect(events[0].end == F.utc("2026-03-10T09:30:00Z"))
        #expect(events[0].meetingLink?.provider == .teams)
        #expect(events[1].meetingLink?.provider == .zoom)
        #expect(events[0].account.kind == .outlook)
        #expect(events[0].id == "microsoft365.AAMk-1")
    }

    @Test func skipsCancelledAndSnapsAllDayToLocalMidnight() throws {
        let page = try JSONDecoder().decode(MicrosoftGraphEventPage.self, from: Data(Self.pageTwo.utf8))
        let events = MicrosoftGraphEventMapper.events(from: page.value, context: Self.context)
        let midnight = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 10)))

        #expect(events.map(\.title) == ["Offsite"])
        #expect(events[0].isAllDay)
        #expect(events[0].start == midnight)
        #expect(events[0].meetingLink?.provider == .zoom)
    }

    @Test func followsNextLinkAndSendsHeaders() async throws {
        let http = CalendarTestHTTPClient(sequence: [.json(Self.pageOne), .json(Self.pageTwo)])
        let client = MicrosoftGraphCalendarClient(http: http)

        let events = try await client.calendarView(
            accessToken: "token-1",
            from: F.utc("2026-03-10T00:00:00Z"),
            to: F.utc("2026-03-12T00:00:00Z")
        )

        #expect(events.map(\.id) == ["AAMk-1", "AAMk-2", "AAMk-3", "AAMk-4"])
        #expect(http.requests.count == 2)
        let first = try #require(http.requests.first)
        let query = first.url?.query(percentEncoded: false) ?? ""
        #expect(first.url?.host() == "graph.microsoft.com")
        #expect(first.url?.path() == "/v1.0/me/calendarView")
        #expect(query.contains("startDateTime=2026-03-10T00:00:00Z"))
        #expect(query.contains("endDateTime=2026-03-12T00:00:00Z"))
        #expect(query.contains("$select=subject,start,end,isAllDay,location,onlineMeeting,onlineMeetingUrl,bodyPreview"))
        #expect(first.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(first.value(forHTTPHeaderField: "Prefer")?.contains(#"outlook.timezone="UTC""#) == true)
        #expect(http.requests.last?.url?.absoluteString.contains("$skip=2") == true)
    }

    @Test func refusesToFollowForeignNextLink() async {
        let page = #"{"value": [], "@odata.nextLink": "https://evil.example.com/steal"}"#
        let http = CalendarTestHTTPClient(sequence: [.json(page)])
        let client = MicrosoftGraphCalendarClient(http: http)

        await #expect(throws: MicrosoftGraphError.untrustedNextLink) {
            try await client.calendarView(accessToken: "t", from: Date(), to: Date().addingTimeInterval(60))
        }
        #expect(http.requests.count == 1)
    }

    @Test func mapsUnauthorized() async {
        let client = MicrosoftGraphCalendarClient(http: CalendarTestHTTPClient(sequence: [.json("{}", status: 401)]))
        await #expect(throws: MicrosoftGraphError.unauthorized) {
            try await client.calendarView(accessToken: "t", from: Date(), to: Date().addingTimeInterval(60))
        }
    }

    @Test func validatesConfiguration() {
        let valid = MicrosoftGraphConfiguration.validated(clientID: " 11111111-2222-3333-4444-555555555555 ", tenant: "")
        #expect(valid?.tenant == "organizations")
        #expect(valid?.tokenURL?.absoluteString == "https://login.microsoftonline.com/organizations/oauth2/v2.0/token")
        #expect(valid?.deviceCodeURL?.absoluteString == "https://login.microsoftonline.com/organizations/oauth2/v2.0/devicecode")
        #expect(MicrosoftGraphConfiguration.validated(clientID: "11111111-2222-3333-4444-555555555555", tenant: "contoso.onmicrosoft.com") != nil)
        #expect(MicrosoftGraphConfiguration.validated(clientID: "not-a-guid", tenant: "") == nil)
        #expect(MicrosoftGraphConfiguration.validated(clientID: "11111111-2222-3333-4444-555555555555", tenant: "evil/../x") == nil)
    }
}
