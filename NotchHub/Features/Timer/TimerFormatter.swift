import Foundation

/// Countdown text formatting. Remaining time is rounded up to whole seconds so
/// "0:01" is shown until the timer actually ends.
enum TimerFormatter {
    private static let secondsPerMinute = 60
    private static let secondsPerHour = 3600
    /// Below this, the compact form shows minutes and seconds ("9:59").
    private static let compactSecondsThreshold = 600

    /// Full clock text: "4:05", "25:00", "1:02:03".
    static func clock(_ remaining: TimeInterval) -> String {
        let total = wholeSeconds(remaining)
        let hours = total / secondsPerHour
        let minutes = (total % secondsPerHour) / secondsPerMinute
        let seconds = total % secondsPerMinute
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Short text for the closed-notch glyph: "1h", "13m", "9:59", "0:05".
    static func compact(_ remaining: TimeInterval) -> String {
        let total = wholeSeconds(remaining)
        if total >= secondsPerHour {
            return "\(total / secondsPerHour)sa"
        }
        if total >= compactSecondsThreshold {
            return "\(ceilDiv(total, secondsPerMinute))dk"
        }
        return clock(TimeInterval(total))
    }

    static func minutesLabel(_ duration: TimeInterval) -> String {
        "\(Int((duration / TimeInterval(secondsPerMinute)).rounded())) dk"
    }

    private static func wholeSeconds(_ interval: TimeInterval) -> Int {
        guard interval.isFinite, interval > 0 else { return 0 }
        return Int(interval.rounded(.up))
    }

    private static func ceilDiv(_ value: Int, _ divisor: Int) -> Int {
        (value + divisor - 1) / divisor
    }
}
