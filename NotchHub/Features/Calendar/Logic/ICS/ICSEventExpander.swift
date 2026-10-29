import Foundation

/// Turns parsed VEVENTs into `CalendarEvent` occurrences for a window (recurrences, EXDATE, RECURRENCE-ID, cancellations).
enum ICSEventExpander {
    static let untitledEventTitle = "Untitled event"
    private static let allDayDuration: TimeInterval = 24 * 60 * 60

    static func events(in data: ICSCalendarData, window: DateInterval, context: CalendarSourceContext) -> [CalendarEvent] {
        let masters = data.events.filter { $0.recurrenceID == nil }
        let overrides = data.events.filter { $0.recurrenceID != nil }
        let mastersByUID = Dictionary(masters.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        let overriddenKeys = Dictionary(grouping: overrides, by: \.uid)
            .mapValues { Set($0.compactMap(\.recurrenceID).map(ICSRecurrenceExpander.key)) }

        var result: [CalendarEvent] = []
        for master in masters where !master.isCancelled {
            result += occurrences(of: master, skipping: overriddenKeys[master.uid] ?? [], in: window, context: context)
        }
        for override in overrides where !override.isCancelled {
            let master = mastersByUID[override.uid]
            if master?.isCancelled == true { continue }
            if let event = overrideEvent(override, master: master, in: window, context: context) {
                result.append(event)
            }
        }
        return result
    }

    /// Meeting link from Teams/Skype properties first, then URL, location and description.
    static func meetingLink(for event: ICSRawEvent) -> MeetingLink? {
        let candidates = [event.teamsMeetingURL, event.conferenceLink, event.url, event.location, event.description]
        for candidate in candidates.compactMap({ $0 }) {
            if let link = MeetingLinkParser.parse(url: nil, location: candidate, notes: nil) {
                return link
            }
        }
        return nil
    }

    // MARK: - Private

    private static func occurrences(
        of master: ICSRawEvent,
        skipping overridden: Set<Int>,
        in window: DateInterval,
        context: CalendarSourceContext
    ) -> [CalendarEvent] {
        guard let start = master.start else { return [] }
        let duration = duration(of: master, start: start)
        guard let rule = master.rule else {
            return overlaps(start.date, duration: duration, window: window)
                ? [makeEvent(master, start: start.date, duration: duration, isAllDay: start.isAllDay, context: context)]
                : []
        }
        let exceptions = Set(master.exceptionDates.map(ICSRecurrenceExpander.key)).union(overridden)
        return ICSRecurrenceExpander
            .occurrences(of: start, rule: rule, duration: duration, excluding: exceptions, in: window)
            .map { makeEvent(master, start: $0, duration: duration, isAllDay: start.isAllDay, context: context) }
    }

    /// The master's start moved to the override's RECURRENCE-ID. Kept as a separate function:
    /// the inline optional chain crashes the Swift 6.3 type checker.
    private static func inheritedStart(of override: ICSRawEvent, master: ICSRawEvent?) -> ICSDateTime? {
        guard let masterStart = master?.start else { return nil }
        let date = override.recurrenceID ?? masterStart.date
        return ICSDateTime(date: date, isAllDay: masterStart.isAllDay, timeZone: masterStart.timeZone)
    }

    private static func overrideEvent(
        _ override: ICSRawEvent,
        master: ICSRawEvent?,
        in window: DateInterval,
        context: CalendarSourceContext
    ) -> CalendarEvent? {
        let masterDuration = master.flatMap { event in event.start.map { duration(of: event, start: $0) } }
        guard let start = override.start ?? inheritedStart(of: override, master: master) else { return nil }
        let hasOwnEnd = override.end != nil || override.duration != nil
        let duration = hasOwnEnd ? duration(of: override, start: start) : (masterDuration ?? duration(of: override, start: start))
        guard overlaps(start.date, duration: duration, window: window) else { return nil }
        let merged = merge(override, into: master)
        return makeEvent(merged, start: start.date, duration: duration, isAllDay: start.isAllDay, context: context)
    }

    private static func merge(_ override: ICSRawEvent, into master: ICSRawEvent?) -> ICSRawEvent {
        guard let master else { return override }
        var merged = override
        merged.summary = override.summary ?? master.summary
        merged.location = override.location ?? master.location
        merged.description = override.description ?? master.description
        merged.url = override.url ?? master.url
        merged.teamsMeetingURL = override.teamsMeetingURL ?? master.teamsMeetingURL
        merged.conferenceLink = override.conferenceLink ?? master.conferenceLink
        return merged
    }

    private static func duration(of event: ICSRawEvent, start: ICSDateTime) -> TimeInterval {
        if let end = event.end, end.date >= start.date {
            return end.date.timeIntervalSince(start.date)
        }
        if let duration = event.duration, duration >= 0 {
            return duration
        }
        return start.isAllDay ? allDayDuration : 0
    }

    private static func overlaps(_ start: Date, duration: TimeInterval, window: DateInterval) -> Bool {
        start < window.end && (start >= window.start || start.addingTimeInterval(duration) > window.start)
    }

    private static func makeEvent(
        _ raw: ICSRawEvent,
        start: Date,
        duration: TimeInterval,
        isAllDay: Bool,
        context: CalendarSourceContext
    ) -> CalendarEvent {
        CalendarEvent(
            id: "\(context.idPrefix).\(raw.uid)@\(Int(start.timeIntervalSince1970))",
            title: raw.summary ?? untitledEventTitle,
            start: start,
            end: start.addingTimeInterval(duration),
            isAllDay: isAllDay,
            calendarColor: context.color,
            location: raw.location,
            meetingLink: meetingLink(for: raw),
            calendarID: context.calendarID,
            calendarTitle: context.calendarTitle,
            account: context.account
        )
    }
}
