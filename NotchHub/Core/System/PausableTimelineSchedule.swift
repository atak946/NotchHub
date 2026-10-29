import SwiftUI

/// A periodic `TimelineView` schedule that produces a single entry while paused, so a hidden or static
/// view (paused media, no meeting running) does not redraw on a timer.
struct PausablePeriodicSchedule: TimelineSchedule {
    let interval: TimeInterval
    let isPaused: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        let step = max(interval, 0.001)
        var next: Date? = startDate
        let paused = isPaused
        return AnyIterator {
            guard let current = next else { return nil }
            next = paused ? nil : current.addingTimeInterval(step)
            return current
        }
    }
}

extension TimelineSchedule where Self == PausablePeriodicSchedule {
    static func periodic(every interval: TimeInterval, paused: Bool) -> PausablePeriodicSchedule {
        PausablePeriodicSchedule(interval: interval, isPaused: paused)
    }
}
