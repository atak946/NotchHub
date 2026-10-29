import Foundation

/// When the pre-meeting "check your camera" alert fires: once per event, only for meetings with a video link.
enum CameraReminderPolicy {
    static let leadTimeOptions: [TimeInterval] = [60, 2 * 60, 5 * 60]
    static let defaultLeadTime: TimeInterval = 2 * 60

    static func isEligible(_ event: CalendarEvent) -> Bool {
        !event.isAllDay && event.meetingLink != nil
    }

    /// Eligible events whose window `[start − lead, start)` contains `date`, earliest first.
    static func dueEvents(
        in events: [CalendarEvent],
        at date: Date,
        leadTime: TimeInterval,
        alreadyFired: Set<String>
    ) -> [CalendarEvent] {
        guard leadTime > 0 else { return [] }
        return unique(events)
            .filter { event in
                isEligible(event)
                    && !alreadyFired.contains(event.id)
                    && event.start.addingTimeInterval(-leadTime) <= date
                    && date < event.start
            }
            .sorted(by: CalendarSchedule.startsBefore)
    }

    /// The next moment a not-yet-fired eligible event enters its window, if any is still ahead.
    static func nextFireDate(
        in events: [CalendarEvent],
        at date: Date,
        leadTime: TimeInterval,
        alreadyFired: Set<String>
    ) -> Date? {
        guard leadTime > 0 else { return nil }
        return unique(events)
            .filter { isEligible($0) && !alreadyFired.contains($0.id) }
            .map { $0.start.addingTimeInterval(-leadTime) }
            .filter { $0 > date }
            .min()
    }

    private static func unique(_ events: [CalendarEvent]) -> [CalendarEvent] {
        var seen = Set<String>()
        return events.filter { seen.insert($0.id).inserted }
    }
}
