import Foundation

/// Pure selection rules for which events are shown and reminded.
enum CalendarSchedule {
    /// How far ahead we look so that tomorrow-morning meetings still get a "next" and a reminder.
    static let lookahead: TimeInterval = 24 * 60 * 60

    /// The window fetched from the event source: the whole of today plus the lookahead.
    static func fetchInterval(at date: Date, calendar: Calendar) -> DateInterval {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = endOfDay(for: date, calendar: calendar)
        return DateInterval(start: startOfDay, end: max(endOfDay, date.addingTimeInterval(lookahead)))
    }

    static func endOfDay(for date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(lookahead)
    }

    static func visible(_ events: [CalendarEvent], hiddenCalendarIDs: Set<String>) -> [CalendarEvent] {
        guard !hiddenCalendarIDs.isEmpty else { return events }
        return events.filter { !hiddenCalendarIDs.contains($0.calendarID) }
    }

    /// The next timed event that has not ended yet; an in-progress event counts.
    static func nextEvent(in events: [CalendarEvent], at date: Date) -> CalendarEvent? {
        events
            .filter { !$0.isAllDay && !$0.hasEnded(at: date) }
            .min(by: startsBefore)
    }

    /// Everything that has not ended and overlaps the rest of today; all-day events first.
    static func remainingToday(in events: [CalendarEvent], at date: Date, calendar: Calendar) -> [CalendarEvent] {
        let endOfDay = endOfDay(for: date, calendar: calendar)
        return events
            .filter { !$0.hasEnded(at: date) && $0.start < endOfDay }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return startsBefore(lhs, rhs)
            }
    }

    /// Timed events whose reminder moment (start − lead time) has passed but which have not started yet.
    static func dueReminders(
        in events: [CalendarEvent],
        at date: Date,
        leadTime: TimeInterval,
        alreadyFired: Set<String>
    ) -> [CalendarEvent] {
        guard leadTime > 0 else { return [] }
        return events
            .filter { event in
                !event.isAllDay
                    && !alreadyFired.contains(event.id)
                    && event.start.addingTimeInterval(-leadTime) <= date
                    && date < event.start
            }
            .sorted(by: startsBefore)
    }

    static func startsBefore(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        if lhs.end != rhs.end { return lhs.end < rhs.end }
        return lhs.id < rhs.id
    }
}
