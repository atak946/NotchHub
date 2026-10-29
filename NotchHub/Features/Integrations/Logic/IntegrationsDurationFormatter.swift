import Foundation

/// Compact elapsed-time text for command alerts: `45s`, `1m 12s`, `2m`, `1h 5m`.
enum IntegrationsDurationFormatter {
    private static let secondsPerMinute = 60
    private static let secondsPerHour = 3600

    static func text(for elapsed: TimeInterval) -> String {
        guard elapsed.isFinite, elapsed >= 1 else { return String(localized: "<1sn") }
        let total = Int(elapsed.rounded(.down))
        let hours = total / secondsPerHour
        let minutes = (total % secondsPerHour) / secondsPerMinute
        let seconds = total % secondsPerMinute

        if hours > 0 {
            return minutes > 0 ? String(localized: "\(hours)sa \(minutes)dk") : String(localized: "\(hours)sa")
        }
        if minutes > 0 {
            return seconds > 0 ? String(localized: "\(minutes)dk \(seconds)sn") : String(localized: "\(minutes)dk")
        }
        return String(localized: "\(seconds)sn")
    }
}
