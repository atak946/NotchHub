import Foundation
import Testing
@testable import NotchHub

struct CameraReminderPolicyTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let lead: TimeInterval = 120

    private func event(_ id: String, start: Date, video: Bool = true, allDay: Bool = false) -> CalendarEvent {
        let link = video ? MeetingLink(provider: .zoom, url: URL(fileURLWithPath: "/zoom")) : nil
        return CalendarEvent(id: id, title: id, start: start, end: start.addingTimeInterval(1800), isAllDay: allDay, meetingLink: link)
    }

    @Test func dueOnlyInsideTheLeadWindow() {
        let meeting = event("a", start: start)

        #expect(CameraReminderPolicy.dueEvents(in: [meeting], at: start.addingTimeInterval(-121), leadTime: lead, alreadyFired: []).isEmpty)
        #expect(CameraReminderPolicy.dueEvents(in: [meeting], at: start.addingTimeInterval(-120), leadTime: lead, alreadyFired: []) == [meeting])
        #expect(CameraReminderPolicy.dueEvents(in: [meeting], at: start, leadTime: lead, alreadyFired: []).isEmpty)
    }

    @Test func onlyVideoMeetings() {
        let date = start.addingTimeInterval(-60)
        let events = [event("plain", start: start, video: false), event("allDay", start: start, allDay: true)]

        #expect(CameraReminderPolicy.dueEvents(in: events, at: date, leadTime: lead, alreadyFired: []).isEmpty)
    }

    @Test func alreadyFiredEventsAreSkippedAndDuplicatesCollapse() {
        let meeting = event("a", start: start)
        let date = start.addingTimeInterval(-60)

        #expect(CameraReminderPolicy.dueEvents(in: [meeting, meeting], at: date, leadTime: lead, alreadyFired: []).count == 1)
        #expect(CameraReminderPolicy.dueEvents(in: [meeting], at: date, leadTime: lead, alreadyFired: ["a"]).isEmpty)
    }

    @Test func nextFireDateIsTheEarliestUpcomingWindow() {
        let later = event("later", start: start.addingTimeInterval(3600))
        let sooner = event("sooner", start: start)
        let date = start.addingTimeInterval(-1000)

        let next = CameraReminderPolicy.nextFireDate(in: [later, sooner], at: date, leadTime: lead, alreadyFired: [])

        #expect(next == start.addingTimeInterval(-lead))
    }
}

@MainActor
struct CameraReminderServiceTests {
    private static let neverSleep: NotchAlertCenter.Sleeper = { _ in try await Task.sleep(for: .seconds(3600)) }
    private let meetingStart = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let defaults: UserDefaults

    init() {
        let suite = "CameraReminderServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
    }

    private func meeting(video: Bool = true) -> CalendarEvent {
        CalendarEvent(
            id: "m1",
            title: "Standup",
            start: meetingStart,
            end: meetingStart.addingTimeInterval(900),
            meetingLink: video ? MeetingLink(provider: .teams, url: URL(fileURLWithPath: "/teams")) : nil
        )
    }

    private func makeService(
        clock: CalendarTestClock,
        alerts: NotchAlertCenter,
        events: [CalendarEvent],
        onCheck: @escaping @MainActor () -> Void = {}
    ) -> CameraReminderService {
        CameraReminderService(
            alerts: alerts,
            defaults: defaults,
            now: { clock.now },
            sleep: Self.neverSleep,
            events: { events },
            onCheckCamera: onCheck
        )
    }

    @Test func defaultsToOnWithTwoMinutes() {
        let service = makeService(clock: CalendarTestClock(meetingStart), alerts: NotchAlertCenter(sleep: Self.neverSleep), events: [])

        #expect(service.isEnabled)
        #expect(service.leadTime == 120)
    }

    @Test func firesOncePerEventInsideTheWindow() {
        let clock = CalendarTestClock(meetingStart.addingTimeInterval(-90))
        let alerts = NotchAlertCenter(sleep: Self.neverSleep)
        let service = makeService(clock: clock, alerts: alerts, events: [meeting()])

        service.start()
        #expect(alerts.current?.actionTitle == "Kamerayı kontrol et")
        alerts.dismiss()

        clock.advance(by: 30)
        service.reschedule()
        #expect(alerts.current == nil)
    }

    @Test func doesNotFireBeforeTheWindow() {
        let clock = CalendarTestClock(meetingStart.addingTimeInterval(-300))
        let alerts = NotchAlertCenter(sleep: Self.neverSleep)
        let service = makeService(clock: clock, alerts: alerts, events: [meeting()])

        service.start()

        #expect(alerts.current == nil)
    }

    @Test func ignoresMeetingsWithoutVideo() {
        let clock = CalendarTestClock(meetingStart.addingTimeInterval(-60))
        let alerts = NotchAlertCenter(sleep: Self.neverSleep)
        let service = makeService(clock: clock, alerts: alerts, events: [meeting(video: false)])

        service.start()

        #expect(alerts.current == nil)
    }

    @Test func respectsTheSetting() {
        let clock = CalendarTestClock(meetingStart.addingTimeInterval(-60))
        let alerts = NotchAlertCenter(sleep: Self.neverSleep)
        let service = makeService(clock: clock, alerts: alerts, events: [meeting()])
        service.isEnabled = false

        service.start()

        #expect(alerts.current == nil)
    }

    @Test func respectsCanPost() {
        let clock = CalendarTestClock(meetingStart.addingTimeInterval(-60))
        let alerts = NotchAlertCenter(sleep: Self.neverSleep)
        let service = makeService(clock: clock, alerts: alerts, events: [meeting()])
        service.canPost = { false }

        service.start()

        #expect(alerts.current == nil)
    }

    @Test func longerLeadTimeFiresEarlier() {
        let clock = CalendarTestClock(meetingStart.addingTimeInterval(-240))
        let alerts = NotchAlertCenter(sleep: Self.neverSleep)
        let service = makeService(clock: clock, alerts: alerts, events: [meeting()])
        service.leadTime = 300

        service.start()

        #expect(alerts.current != nil)
    }

    @Test func actionOpensTheMirrorButThePostAloneDoesNot() {
        let clock = CalendarTestClock(meetingStart.addingTimeInterval(-60))
        let alerts = NotchAlertCenter(sleep: Self.neverSleep)
        var checks = 0
        let service = makeService(clock: clock, alerts: alerts, events: [meeting()]) { checks += 1 }

        service.start()
        #expect(checks == 0)

        alerts.performAction()
        #expect(checks == 1)
    }
}
