import Foundation

/// Subset of the Graph `event` resource requested via `$select`.
struct MicrosoftGraphEvent: Decodable, Equatable, Sendable {
    struct DateTimeTimeZone: Decodable, Equatable, Sendable {
        let dateTime: String
        let timeZone: String?
    }

    struct Location: Decodable, Equatable, Sendable {
        let displayName: String?
    }

    struct OnlineMeeting: Decodable, Equatable, Sendable {
        let joinUrl: String?
    }

    struct Body: Decodable, Equatable, Sendable {
        let content: String?
    }

    let id: String
    let subject: String?
    let start: DateTimeTimeZone
    let end: DateTimeTimeZone
    let isAllDay: Bool?
    let location: Location?
    let onlineMeeting: OnlineMeeting?
    let onlineMeetingUrl: String?
    let bodyPreview: String?
    let body: Body?
    let webLink: String?
    let isCancelled: Bool?
}

/// One page of `/me/calendarView`.
struct MicrosoftGraphEventPage: Decodable, Sendable {
    let value: [MicrosoftGraphEvent]
    let nextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

struct MicrosoftGraphUser: Decodable, Sendable {
    let displayName: String?
    let userPrincipalName: String?
    let mail: String?
}

/// Maps Graph events to `CalendarEvent`s; meeting links come from `onlineMeeting.joinUrl` or `MeetingLinkParser`.
enum MicrosoftGraphEventMapper {
    static let untitledEventTitle = String(localized: "Untitled event")
    private static let dateTimePrefixLength = 19
    private static let secondsPerDay: TimeInterval = 24 * 60 * 60

    static func events(from graphEvents: [MicrosoftGraphEvent], context: CalendarSourceContext) -> [CalendarEvent] {
        graphEvents.compactMap { event(from: $0, context: context) }
    }

    static func event(from graph: MicrosoftGraphEvent, context: CalendarSourceContext) -> CalendarEvent? {
        guard graph.isCancelled != true else { return nil }
        let isAllDay = graph.isAllDay ?? false
        guard let start = date(from: graph.start, isAllDay: isAllDay), let rawEnd = date(from: graph.end, isAllDay: isAllDay) else {
            return nil
        }
        let subject = graph.subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let location = graph.location?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return CalendarEvent(
            id: "\(context.idPrefix).\(graph.id)",
            title: subject.isEmpty ? untitledEventTitle : subject,
            start: start,
            end: max(start, rawEnd),
            isAllDay: isAllDay,
            calendarColor: context.color,
            location: location.isEmpty ? nil : location,
            meetingLink: meetingLink(for: graph),
            calendarID: context.calendarID,
            calendarTitle: context.calendarTitle,
            account: context.account
        )
    }

    static func meetingLink(for graph: MicrosoftGraphEvent) -> MeetingLink? {
        let joinURL = [graph.onlineMeeting?.joinUrl, graph.onlineMeetingUrl]
            .compactMap { $0 }
            .compactMap { URL(string: $0) }
            .first
        let notes = [graph.body?.content, graph.bodyPreview].compactMap { $0 }.joined(separator: "\n")
        return MeetingLinkParser.parse(url: joinURL, location: graph.location?.displayName, notes: notes.isEmpty ? nil : notes)
    }

    /// Parses `2026-03-10T09:00:00.0000000` in the given zone (UTC thanks to the `Prefer` header).
    /// All-day events are snapped to local midnight: Graph may report them in UTC, which would shift the day.
    static func date(from value: MicrosoftGraphEvent.DateTimeTimeZone, isAllDay: Bool) -> Date? {
        let text = Array(value.dateTime.prefix(dateTimePrefixLength))
        guard text.count == dateTimePrefixLength,
              let year = Int(String(text[0..<4])), let month = Int(String(text[5..<7])), let day = Int(String(text[8..<10])),
              let hour = Int(String(text[11..<13])), let minute = Int(String(text[14..<16])), let second = Int(String(text[17..<19]))
        else { return nil }
        let zone = value.timeZone.flatMap { ICSTimeZoneResolver.timeZone(for: $0) } ?? TimeZone(identifier: "UTC") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let instant = calendar.date(from: components) else { return nil }
        return isAllDay ? localMidnight(nearest: instant) : instant
    }

    private static func localMidnight(nearest instant: Date) -> Date {
        let local = Calendar.current
        let halfDay = secondsPerDay / 2
        return local.startOfDay(for: instant.addingTimeInterval(halfDay))
    }
}
