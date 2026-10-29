import Foundation

/// Short text formatting shared by the System tiles and alerts.
enum SystemFormat {
    private static let secondsPerMinute = 60
    private static let secondsPerHour = 3600

    /// "mm:ss" below one hour, "h:mm:ss" above.
    static func elapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / secondsPerHour
        let minutes = (total % secondsPerHour) / secondsPerMinute
        let seconds = total % secondsPerMinute
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Decimal (Finder-style) byte count, e.g. "12.4 GB".
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
