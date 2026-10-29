import Foundation
import Testing
@testable import NotchHub

struct NoteTitleTests {
    private let utc = TimeZone(identifier: "UTC")!
    /// 2023-11-14 22:13:20 UTC
    private let created = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func firstNonEmptyLineWins() {
        let note = Note(body: "\n   \n  Kickoff notes  \nsecond", createdAt: created, meetingTitle: "Sync")
        #expect(note.displayTitle(timeZone: utc) == "Kickoff notes")
    }

    @Test func emptyMeetingNoteUsesMeetingAndTime() {
        let note = Note(body: "  \n", createdAt: created, meetingTitle: "Sprint review")
        #expect(note.displayTitle(timeZone: utc) == "Toplantı: Sprint review · 22:13")
    }

    @Test func emptyNoteWithoutMeetingIsUntitled() {
        #expect(Note(createdAt: created).displayTitle(timeZone: utc) == Note.untitled)
        #expect(Note(createdAt: created, meetingTitle: "  ").displayTitle(timeZone: utc) == Note.untitled)
    }

    @Test func meetingTitleUsesOnlyInProgressTimedEvents() {
        let now = created
        let past = CalendarEvent(id: "p", title: "Past", start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600))
        let allDay = CalendarEvent(id: "a", title: "Holiday", start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(3600), isAllDay: true)
        let live = CalendarEvent(id: "l", title: " Design sync ", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(600))
        let future = CalendarEvent(id: "f", title: "Later", start: now.addingTimeInterval(600), end: now.addingTimeInterval(1200))

        #expect(LiveNoteContextProvider.meetingTitle(in: [past, allDay, live, future], at: now) == "Design sync")
        #expect(LiveNoteContextProvider.meetingTitle(in: [past, allDay, future], at: now) == nil)
    }
}
