import EventKit
import Foundation
import Testing
@testable import NotchHub

struct CalendarAccountKindTests {
    @Test(arguments: [
        (EKSourceType.exchange, "Work", CalendarAccountKind.outlook),
        (.calDAV, "Outlook", .outlook),
        (.calDAV, "me@hotmail.com", .outlook),
        (.calDAV, "Office365", .outlook),
        (.calDAV, "me@live.com", .outlook),
        (.calDAV, "Live", .outlook),
        (.calDAV, "me@gmail.com", .google),
        (.calDAV, "Google", .google),
        (.calDAV, "iCloud", .iCloud),
        (.mobileMe, "Anything", .iCloud),
        (.calDAV, "Fastmail", .other),
        (.calDAV, "Delivery schedule", .other),
        (.local, "Bu Mac'te", .local),
        (.subscribed, "Holidays", .subscribed),
        (.birthdays, "Birthdays", .subscribed),
    ])
    func classifies(sourceType: EKSourceType, title: String, expected: CalendarAccountKind) {
        #expect(CalendarAccountKind.classify(sourceType: sourceType, title: title) == expected)
    }

    @Test func displayTitleFallsBackToKindName() {
        #expect(CalendarAccount(id: "x", title: "", kind: .google).displayTitle == "Google")
        #expect(CalendarAccount(id: "x", title: "me@gmail.com", kind: .google).displayTitle == "me@gmail.com")
    }
}

struct CalendarEventGrouperTests {
    private typealias F = CalendarFixtures

    @Test func returnsNoGroupsForNoEvents() {
        for grouping in CalendarGrouping.allCases {
            #expect(CalendarEventGrouper.groups(for: [], by: grouping).isEmpty)
        }
    }

    @Test func noneGroupingReturnsSingleSortedGroup() {
        let events = [F.event("b", start: F.date(hour: 11)), F.event("a", start: F.date(hour: 9))]
        let groups = CalendarEventGrouper.groups(for: events, by: .none)

        #expect(groups.count == 1)
        #expect(groups.first?.events.map(\.id) == ["a", "b"])
    }

    @Test func groupsByAccountOrderedByEarliestEvent() {
        let events = [
            F.event("g-late", start: F.date(hour: 15), account: F.google),
            F.event("o-mid", start: F.date(hour: 11), account: F.outlook),
            F.event("g-early", start: F.date(hour: 9), account: F.google),
            F.event("o-late", start: F.date(hour: 16), account: F.outlook),
        ]
        let groups = CalendarEventGrouper.groups(for: events, by: .account)

        #expect(groups.map(\.title) == ["me@gmail.com", "Work (Outlook)"])
        #expect(groups.map(\.systemImage) == [CalendarAccountKind.google.systemImage, CalendarAccountKind.outlook.systemImage])
        #expect(groups[0].events.map(\.id) == ["g-early", "g-late"])
        #expect(groups[1].events.map(\.id) == ["o-mid", "o-late"])
        #expect(Set(groups.map(\.id)).count == groups.count)
    }

    @Test func groupsByProviderOmittingEmptyGroups() {
        let events = [
            F.event("teams", start: F.date(hour: 13), link: F.link(.teams)),
            F.event("desk", start: F.date(hour: 8)),
            F.event("zoom-2", start: F.date(hour: 14), link: F.link(.zoom)),
            F.event("zoom-1", start: F.date(hour: 10), link: F.link(.zoom)),
            F.event("jitsi", start: F.date(hour: 17), link: F.link(.other)),
        ]
        let groups = CalendarEventGrouper.groups(for: events, by: .provider)

        #expect(groups.map(\.title) == ["Yüz yüze / bağlantısız", "Zoom", "Teams", "Diğer bağlantı"])
        #expect(groups.first { $0.title == "Zoom" }?.events.map(\.id) == ["zoom-1", "zoom-2"])
        #expect(!groups.contains { $0.title == "Meet" || $0.title == "Webex" })
    }

    @Test func meetingGroupKindMapsEveryProvider() {
        #expect(MeetingGroupKind(link: nil) == .noLink)
        #expect(MeetingGroupKind(link: F.link(.meet)) == .meet)
        #expect(MeetingGroupKind(link: F.link(.webex)) == .webex)
        #expect(MeetingGroupKind(link: F.link(.other)).title == "Diğer bağlantı")
    }
}
