import Foundation

/// Trailing time label of an alert: "şimdi", "5 dk", then the clock time.
enum AlertTimestampFormatter {
    static let nowText = "şimdi"
    private static let secondsPerMinute: TimeInterval = 60
    private static let minutesPerHour = 60

    static func text(postedAt: Date, now: Date, calendar: Calendar = .current) -> String {
        let elapsed = now.timeIntervalSince(postedAt)
        let minutes = Int(elapsed / secondsPerMinute)
        if minutes < 1 { return nowText }
        if minutes < minutesPerHour { return "\(minutes) dk" }
        let parts = calendar.dateComponents([.hour, .minute], from: postedAt)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
