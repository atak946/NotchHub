import Foundation

/// Short relative-time labels such as "in 15 min", "now", "in 1 h 20 min", "ends in 10 min".
enum RelativeTimeFormatter {
    private static let secondsPerMinute: Double = 60
    private static let minutesPerHour = 60
    /// After the start, "now" is shown for this long before switching to "ends in …".
    private static let justStartedWindow: TimeInterval = 60

    static var nowText: String { String(localized: "şimdi") }
    static var endedText: String { String(localized: "bitti") }

    static func text(for event: CalendarEvent, at date: Date) -> String {
        if date < event.start {
            let remaining = duration(event.start.timeIntervalSince(date))
            return String(localized: "\(remaining) sonra")
        }
        if event.hasEnded(at: date) {
            return endedText
        }
        if date.timeIntervalSince(event.start) < justStartedWindow {
            return nowText
        }
        let remaining = duration(event.end.timeIntervalSince(date))
        return String(localized: "\(remaining) içinde biter")
    }

    /// Formats a positive interval rounded up to whole minutes: "1 min", "45 min", "2 h", "1 h 20 min".
    static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(1, Int((interval / secondsPerMinute).rounded(.up)))
        let hours = totalMinutes / minutesPerHour
        let minutes = totalMinutes % minutesPerHour
        switch (hours, minutes) {
        case (0, _): return String(localized: "\(minutes) dk")
        case (_, 0): return String(localized: "\(hours) sa")
        default: return String(localized: "\(hours) sa \(minutes) dk")
        }
    }
}
