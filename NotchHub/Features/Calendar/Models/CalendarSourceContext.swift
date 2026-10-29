import Foundation

/// Where events of a remote source (ICS feed, Microsoft 365) belong in NotchHub's account/calendar model.
struct CalendarSourceContext: Equatable, Sendable {
    /// Prefix of every event id, unique per source/feed (e.g. `ics.<feed id>`).
    let idPrefix: String
    let calendarID: String
    let calendarTitle: String
    let color: CalendarColor
    let account: CalendarAccount

    var calendarInfo: CalendarInfo {
        CalendarInfo(id: calendarID, title: calendarTitle, color: color, accountID: account.id)
    }
}
