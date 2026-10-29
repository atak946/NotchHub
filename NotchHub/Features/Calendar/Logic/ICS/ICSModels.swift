import Foundation

/// A resolved DTSTART/DTEND/EXDATE/RECURRENCE-ID value.
struct ICSDateTime: Equatable, Sendable {
    let date: Date
    /// `VALUE=DATE` (all-day). Interpreted as local midnight ("floating").
    let isAllDay: Bool
    /// Zone in which recurrences are expanded (wall-clock stays stable across DST).
    let timeZone: TimeZone
}

enum ICSFrequency: String, Sendable {
    case daily = "DAILY"
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"
    case yearly = "YEARLY"
}

/// `BYDAY` entry such as `MO`, `2TU`, `-1FR`. `weekday` uses `Calendar` numbering (1 = Sunday).
struct ICSWeekdayRule: Equatable, Sendable {
    let weekday: Int
    let ordinal: Int?
}

/// Supported subset of RFC 5545 RRULE.
struct ICSRecurrenceRule: Equatable, Sendable {
    var frequency: ICSFrequency
    var interval: Int = 1
    var count: Int?
    var until: Date?
    var byDay: [ICSWeekdayRule] = []
    var byMonthDay: [Int] = []
    var byMonth: [Int] = []
    var bySetPosition: [Int] = []
    /// Calendar weekday that starts the week (default Monday = 2).
    var weekStart: Int = 2
}

/// A VEVENT as parsed from the feed (master or RECURRENCE-ID override).
struct ICSRawEvent: Equatable, Sendable {
    var uid: String = ""
    var summary: String?
    var start: ICSDateTime?
    var end: ICSDateTime?
    var duration: TimeInterval?
    var rule: ICSRecurrenceRule?
    var exceptionDates: [Date] = []
    var recurrenceID: Date?
    var isCancelled = false
    var location: String?
    var description: String?
    var url: String?
    var teamsMeetingURL: String?
    var conferenceLink: String?
}

struct ICSCalendarData: Equatable, Sendable {
    var name: String?
    var events: [ICSRawEvent] = []

    /// Non-cancelled series/single events (overrides are not counted separately).
    var eventCount: Int {
        events.filter { $0.recurrenceID == nil && !$0.isCancelled && $0.start != nil }.count
    }
}
