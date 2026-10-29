import Foundation
import Testing
@testable import NotchHub

struct CalendarScheduleTests {
    private typealias F = CalendarFixtures

    @Test func inProgressEventIsNext() {
        let now = F.date(hour: 10, minute: 15)
        let running = F.event("running", start: F.date(hour: 10))
        let later = F.event("later", start: F.date(hour: 11))

        #expect(CalendarSchedule.nextEvent(in: [later, running], at: now)?.id == "running")
    }

    @Test func excludesAllDayAndEndedEvents() {
        let now = F.date(hour: 12)
        let allDay = F.event("allDay", start: F.date(hour: 0), minutes: 24 * 60, isAllDay: true)
        let ended = F.event("ended", start: F.date(hour: 11), minutes: 60)
        let upcoming = F.event("upcoming", start: F.date(hour: 15))

        #expect(CalendarSchedule.nextEvent(in: [allDay, ended, upcoming], at: now)?.id == "upcoming")
        #expect(CalendarSchedule.nextEvent(in: [allDay, ended], at: now) == nil)
    }

    @Test func remainingTodayKeepsAllDayFirstAndDropsTomorrow() {
        let now = F.date(hour: 12)
        let allDay = F.event("allDay", start: F.date(hour: 0), minutes: 24 * 60, isAllDay: true)
        let ended = F.event("ended", start: F.date(hour: 9))
        let afternoon = F.event("afternoon", start: F.date(hour: 16))
        let noon = F.event("noon", start: F.date(hour: 11, minute: 45))
        let tomorrow = F.event("tomorrow", start: F.date(hour: 9, dayOffset: 1))

        let ids = CalendarSchedule.remainingToday(in: [tomorrow, afternoon, ended, noon, allDay], at: now, calendar: F.calendar)
            .map(\.id)
        #expect(ids == ["allDay", "noon", "afternoon"])
    }

    @Test func fetchIntervalCoversTodayAndLookahead() {
        let now = F.date(hour: 23)
        let interval = CalendarSchedule.fetchInterval(at: now, calendar: F.calendar)

        #expect(interval.start == F.date(hour: 0))
        #expect(interval.end == now.addingTimeInterval(CalendarSchedule.lookahead))
    }

    @Test func dueRemindersRespectWindowAndFiredSet() {
        let event = F.event("standup", start: F.date(hour: 10))
        let lead: TimeInterval = 5 * 60

        #expect(CalendarSchedule.dueReminders(in: [event], at: F.date(hour: 9, minute: 54), leadTime: lead, alreadyFired: []).isEmpty)
        #expect(CalendarSchedule.dueReminders(in: [event], at: F.date(hour: 9, minute: 55), leadTime: lead, alreadyFired: []).count == 1)
        #expect(CalendarSchedule.dueReminders(in: [event], at: F.date(hour: 9, minute: 58), leadTime: lead, alreadyFired: ["standup"]).isEmpty)
        #expect(CalendarSchedule.dueReminders(in: [event], at: F.date(hour: 10), leadTime: lead, alreadyFired: []).isEmpty)
        #expect(CalendarSchedule.dueReminders(in: [event], at: F.date(hour: 9, minute: 58), leadTime: 0, alreadyFired: []).isEmpty)
    }

    @Test func visibleFiltersHiddenCalendars() {
        let work = F.event("work", start: F.date(hour: 10), calendarID: "work")
        let home = F.event("home", start: F.date(hour: 11), calendarID: "home")

        #expect(CalendarSchedule.visible([work, home], hiddenCalendarIDs: ["home"]).map(\.id) == ["work"])
        #expect(CalendarSchedule.visible([work, home], hiddenCalendarIDs: []).count == 2)
    }
}
