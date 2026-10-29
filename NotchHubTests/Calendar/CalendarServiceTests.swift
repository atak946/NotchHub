import Foundation
import Testing
@testable import NotchHub

@MainActor
struct CalendarServiceTests {
    private typealias F = CalendarFixtures

    private func makeService(
        source: FakeCalendarSource,
        clock: CalendarTestClock,
        defaults: UserDefaults = F.makeDefaults()
    ) -> CalendarService {
        CalendarService(source: source, defaults: defaults, now: { clock.now })
    }

    @Test func publishesNextAndTodayEventsOnRefresh() {
        let source = FakeCalendarSource()
        source.storedEvents = [
            F.event("a", start: F.date(hour: 9)),
            F.event("b", start: F.date(hour: 14)),
            F.event("tomorrow", start: F.date(hour: 9, dayOffset: 1)),
        ]
        let service = makeService(source: source, clock: CalendarTestClock(F.date(hour: 9, minute: 10)))

        service.refresh()

        #expect(service.nextEvent?.id == "a")
        #expect(service.todayEvents.map(\.id) == ["a", "b"])
    }

    @Test func nextEventCanBeTomorrowWhenDayIsClear() {
        let source = FakeCalendarSource()
        source.storedEvents = [F.event("tomorrow", start: F.date(hour: 9, dayOffset: 1))]
        let service = makeService(source: source, clock: CalendarTestClock(F.date(hour: 20)))

        service.refresh()

        #expect(service.todayEvents.isEmpty)
        #expect(service.nextEvent?.id == "tomorrow")
    }

    @Test func clearsStateWhenNotAuthorized() {
        let source = FakeCalendarSource(authorization: .denied)
        source.storedEvents = [F.event("a", start: F.date(hour: 9))]
        let service = makeService(source: source, clock: CalendarTestClock(F.date(hour: 8)))

        service.refresh()

        #expect(service.authorization == .denied)
        #expect(service.nextEvent == nil)
        #expect(service.todayEvents.isEmpty)
    }

    @Test func reminderFiresExactlyOnceAcrossRefreshes() {
        let source = FakeCalendarSource()
        source.storedEvents = [F.event("standup", start: F.date(hour: 10))]
        let clock = CalendarTestClock(F.date(hour: 9, minute: 50))
        let service = makeService(source: source, clock: clock)
        var fired: [String] = []
        service.onReminder = { fired.append($0.id) }

        service.refresh()
        #expect(fired.isEmpty)

        clock.set(F.date(hour: 9, minute: 55))
        service.refresh()
        #expect(fired == ["standup"])

        clock.advance(by: 60)
        service.refresh()
        source.simulateStoreChange()
        clock.advance(by: 60)
        service.refresh()

        #expect(fired == ["standup"])
    }

    @Test func storeChangeTriggersRefreshAfterStart() {
        let source = FakeCalendarSource()
        let service = makeService(source: source, clock: CalendarTestClock(F.date(hour: 9)))
        service.start()
        defer { service.stop() }

        source.storedEvents = [F.event("new", start: F.date(hour: 11))]
        source.simulateStoreChange()

        #expect(service.nextEvent?.id == "new")
    }

    @Test func stopRemovesStoreObserver() {
        let source = FakeCalendarSource()
        let service = makeService(source: source, clock: CalendarTestClock(F.date(hour: 9)))
        service.start()
        #expect(source.changeHandler != nil)
        #expect(service.isRunning)

        service.stop()

        #expect(source.changeHandler == nil)
        #expect(!service.isRunning)
    }

    @Test func remindersUseLeadTimeAndCanBeDisabled() {
        let source = FakeCalendarSource()
        source.storedEvents = [F.event("review", start: F.date(hour: 10))]
        let clock = CalendarTestClock(F.date(hour: 9, minute: 52))
        let service = makeService(source: source, clock: clock)
        var count = 0
        service.onReminder = { _ in count += 1 }

        service.reminderLeadTime = 0
        service.refresh()
        #expect(count == 0)

        service.reminderLeadTime = 10 * 60
        service.refresh()
        #expect(count == 1)
    }

    @Test func remindersSkipHiddenCalendarsAndAllDay() {
        let source = FakeCalendarSource()
        source.storedEvents = [
            F.event("hidden", start: F.date(hour: 10), calendarID: "private"),
            F.event("holiday", start: F.date(hour: 0), minutes: 24 * 60, isAllDay: true),
        ]
        let defaults = F.makeDefaults()
        let service = makeService(source: source, clock: CalendarTestClock(F.date(hour: 9, minute: 57)), defaults: defaults)
        service.hiddenCalendarIDs = ["private"]
        var fired: [String] = []
        service.onReminder = { fired.append($0.id) }

        service.refresh()

        #expect(fired.isEmpty)
        #expect(service.nextEvent == nil)
        #expect(service.todayEvents.map(\.id) == ["holiday"])
    }

    @Test func hidingCalendarUpdatesStateImmediately() {
        let source = FakeCalendarSource()
        source.storedEvents = [
            F.event("work", start: F.date(hour: 10), calendarID: "work"),
            F.event("gym", start: F.date(hour: 9, minute: 30), calendarID: "gym"),
        ]
        let service = makeService(source: source, clock: CalendarTestClock(F.date(hour: 9)))
        service.refresh()
        #expect(service.nextEvent?.id == "gym")

        service.setCalendar("gym", visible: false)
        #expect(service.nextEvent?.id == "work")
        #expect(service.isCalendarHidden("gym"))

        service.setCalendar("gym", visible: true)
        #expect(service.nextEvent?.id == "gym")
    }

    @Test func persistsSettingsAcrossInstances() {
        let defaults = F.makeDefaults()
        let clock = CalendarTestClock(F.date(hour: 9))
        let service = makeService(source: FakeCalendarSource(), clock: clock, defaults: defaults)
        #expect(service.reminderLeadTime == CalendarService.defaultReminderLeadTime)
        #expect(service.grouping == .none)
        #expect(service.hiddenCalendarIDs.isEmpty)

        service.reminderLeadTime = 15 * 60
        service.grouping = .provider
        service.hiddenCalendarIDs = ["a", "b"]

        let reloaded = makeService(source: FakeCalendarSource(), clock: clock, defaults: defaults)
        #expect(reloaded.reminderLeadTime == 15 * 60)
        #expect(reloaded.grouping == .provider)
        #expect(reloaded.hiddenCalendarIDs == ["a", "b"])
    }

    @Test func ignoresInvalidStoredLeadTimeAndGrouping() {
        let defaults = F.makeDefaults()
        defaults.set(42.0, forKey: CalendarService.Keys.reminderLeadTime)
        defaults.set("bogus", forKey: CalendarService.Keys.grouping)

        let service = makeService(source: FakeCalendarSource(), clock: CalendarTestClock(F.date(hour: 9)), defaults: defaults)

        #expect(service.reminderLeadTime == CalendarService.defaultReminderLeadTime)
        #expect(service.grouping == .none)
    }

    @Test func persistsZeroLeadTimeAsOff() {
        let defaults = F.makeDefaults()
        let clock = CalendarTestClock(F.date(hour: 9))
        makeService(source: FakeCalendarSource(), clock: clock, defaults: defaults).reminderLeadTime = 0

        #expect(makeService(source: FakeCalendarSource(), clock: clock, defaults: defaults).reminderLeadTime == 0)
    }

    @Test func requestAccessGrantsAndRefreshes() async {
        let source = FakeCalendarSource(authorization: .notDetermined)
        source.storedEvents = [F.event("a", start: F.date(hour: 10))]
        let service = makeService(source: source, clock: CalendarTestClock(F.date(hour: 9)))
        #expect(service.authorization == .notDetermined)

        service.requestAccess()
        for _ in 0..<50 where service.nextEvent == nil {
            await Task.yield()
        }

        #expect(source.requestCount == 1)
        #expect(service.authorization == .authorized)
        #expect(service.nextEvent?.id == "a")
    }

    @Test func exposesAccountsAndCalendars() {
        let source = FakeCalendarSource()
        source.storedAccounts = [F.outlook, F.google]
        source.storedCalendars = [
            CalendarInfo(id: "c1", title: "Work", color: .fallback, accountID: F.outlook.id),
            CalendarInfo(id: "c2", title: "Personal", color: .fallback, accountID: F.google.id),
        ]
        let service = makeService(source: source, clock: CalendarTestClock(F.date(hour: 9)))

        service.refresh()

        #expect(service.accounts == [F.outlook, F.google])
        #expect(service.calendars(for: F.google).map(\.id) == ["c2"])
    }

    @Test func groupedTodayEventsFollowsGroupingAndExclusion() {
        let source = FakeCalendarSource()
        source.storedEvents = [
            F.event("zoom", start: F.date(hour: 10), account: F.outlook, link: F.link(.zoom)),
            F.event("lunch", start: F.date(hour: 12), account: F.google),
        ]
        let service = makeService(source: source, clock: CalendarTestClock(F.date(hour: 9)))
        service.refresh()

        service.grouping = .provider
        #expect(service.groupedTodayEvents().map(\.title) == ["Zoom", "Yüz yüze / bağlantısız"])
        #expect(service.groupedTodayEvents(excluding: "zoom").map(\.title) == ["Yüz yüze / bağlantısız"])

        service.grouping = .none
        #expect(service.groupedTodayEvents().first?.events.count == 2)
    }
}
