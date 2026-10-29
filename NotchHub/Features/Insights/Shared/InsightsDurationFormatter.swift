import Foundation

/// Compact "6h 40m" style durations used by tiles, alerts and summaries.
enum InsightsDurationFormatter {
    private static let secondsPerMinute = 60
    private static let minutesPerHour = 60

    static func short(seconds: Int) -> String {
        let totalMinutes = max(0, seconds) / secondsPerMinute
        let hours = totalMinutes / minutesPerHour
        let minutes = totalMinutes % minutesPerHour
        switch (hours, minutes) {
        case (0, _): return String(localized: "\(minutes)dk")
        case (_, 0): return String(localized: "\(hours)sa")
        default: return String(localized: "\(hours)sa \(minutes)dk")
        }
    }
}
