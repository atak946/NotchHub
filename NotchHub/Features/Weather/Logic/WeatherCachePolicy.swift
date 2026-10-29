import Foundation

/// When a cached forecast must be refreshed and when it is too old to show at all.
enum WeatherCachePolicy {
    /// Refresh cadence of the forecast.
    static let refreshInterval: TimeInterval = 30 * 60
    /// Older forecasts are hidden rather than shown as current.
    static let maxDisplayAge: TimeInterval = 3 * 60 * 60
    /// A fetch time this far in the future means the clock jumped; such a cache counts as stale.
    static let clockSkewTolerance: TimeInterval = 5 * 60

    static func age(of snapshot: WeatherSnapshot, now: Date) -> TimeInterval {
        now.timeIntervalSince(snapshot.fetchedAt)
    }

    /// True when the snapshot is older than the refresh interval (or dated implausibly in the future).
    static func isStale(_ snapshot: WeatherSnapshot?, now: Date) -> Bool {
        guard let snapshot else { return true }
        let age = age(of: snapshot, now: now)
        return age >= refreshInterval || age < -clockSkewTolerance
    }

    /// True while the snapshot is recent enough to be shown, even if a refresh is due.
    static func isDisplayable(_ snapshot: WeatherSnapshot?, now: Date) -> Bool {
        guard let snapshot else { return false }
        let age = age(of: snapshot, now: now)
        return age < maxDisplayAge && age >= -clockSkewTolerance
    }

    /// Seconds until the snapshot becomes stale; zero when a refresh is already due.
    static func timeUntilStale(_ snapshot: WeatherSnapshot?, now: Date) -> TimeInterval {
        guard let snapshot, !isStale(snapshot, now: now) else { return 0 }
        return max(0, refreshInterval - age(of: snapshot, now: now))
    }
}
