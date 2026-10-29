import Foundation

/// Picks a whole-hour time zone in which "now" is mid-morning, so screenshots always show a busy
/// working day and never reveal the machine's own time zone.
enum DemoClock {
    static let targetHour = 9
    private static let secondsPerHour = 3600
    private static let hoursPerDay = 24
    /// Offsets above this wrap to the negative side, keeping them within UTC-12 … UTC+11.
    private static let highestOffset = 11

    static var timeZone: TimeZone { timeZone(at: Date()) }

    static func timeZone(at date: Date) -> TimeZone {
        TimeZone(secondsFromGMT: offsetHours(at: date) * secondsPerHour) ?? .gmt
    }

    /// The offset in hours (−12…+11) at which `date` falls in `targetHour`.
    static func offsetHours(at date: Date) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let hour = utc.component(.hour, from: date)
        let offset = ((targetHour - hour) % hoursPerDay + hoursPerDay) % hoursPerDay
        return offset > highestOffset ? offset - hoursPerDay : offset
    }

    /// Switches the whole process (formatters included) to the demo time zone.
    static func apply(at date: Date = Date()) {
        setenv("TZ", posixIdentifier(offsetHours: offsetHours(at: date)), 1)
        tzset()
        NSTimeZone.resetSystemTimeZone()
        NSTimeZone.default = timeZone(at: date)
    }

    /// POSIX `Etc/GMT` names have inverted signs: UTC+3 is `Etc/GMT-3`.
    static func posixIdentifier(offsetHours: Int) -> String {
        offsetHours == 0 ? "Etc/GMT" : "Etc/GMT\(offsetHours > 0 ? "-" : "+")\(abs(offsetHours))"
    }
}
