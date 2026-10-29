import Foundation

/// Sendable sRGB color of a calendar (EventKit hands out `NSColor`, which is not `Sendable`).
struct CalendarColor: Hashable, Sendable {
    static let fallback = CalendarColor(red: 0.55, green: 0.55, blue: 0.6)

    let red: Double
    let green: Double
    let blue: Double
}

/// Permission state for reading the user's calendars.
enum CalendarAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

/// One calendar (e.g. "Work", "Birthdays") belonging to an account.
struct CalendarInfo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let color: CalendarColor
    let accountID: String
}

/// A single calendar event occurrence, decoupled from EventKit.
struct CalendarEvent: Identifiable, Equatable, Sendable {
    /// Unique per occurrence (recurring events share their EventKit identifier, so the start date is appended).
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarColor: CalendarColor
    let location: String?
    let meetingLink: MeetingLink?
    let calendarID: String
    let calendarTitle: String
    let account: CalendarAccount

    init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        calendarColor: CalendarColor = .fallback,
        location: String? = nil,
        meetingLink: MeetingLink? = nil,
        calendarID: String = "",
        calendarTitle: String = "",
        account: CalendarAccount = .unknown
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarColor = calendarColor
        self.location = location
        self.meetingLink = meetingLink
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.account = account
    }

    func isInProgress(at date: Date) -> Bool {
        start <= date && date < end
    }

    func hasEnded(at date: Date) -> Bool {
        end <= date
    }
}
