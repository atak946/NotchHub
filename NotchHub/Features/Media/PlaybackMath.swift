import Foundation

/// Pure helpers for playback position, seeking and source selection.
enum PlaybackMath {
    /// Clamps a position into `0...duration`. Unknown durations (0) only clamp the lower bound.
    static func clamp(_ position: TimeInterval, duration: TimeInterval) -> TimeInterval {
        guard position.isFinite else { return 0 }
        let lowerBounded = max(position, 0)
        guard duration > 0 else { return lowerBounded }
        return min(lowerBounded, duration)
    }

    /// Position extrapolated from the last snapshot, advancing only while playing.
    static func interpolatedPosition(
        base: TimeInterval,
        snapshotDate: Date,
        now: Date,
        isPlaying: Bool,
        duration: TimeInterval
    ) -> TimeInterval {
        let elapsed = isPlaying ? max(now.timeIntervalSince(snapshotDate), 0) : 0
        return clamp(base + elapsed, duration: duration)
    }

    /// Fraction of the track played, in `0...1`.
    static func progress(position: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return clamp(position, duration: duration) / duration
    }

    /// Position for a fraction of the progress bar.
    static func position(forFraction fraction: Double, duration: TimeInterval) -> TimeInterval {
        guard fraction.isFinite, duration > 0 else { return 0 }
        return min(max(fraction, 0), 1) * duration
    }
}

enum MediaSourceSelector {
    /// Picks the track to show when several players report one.
    ///
    /// A playing track always wins; among equals the currently shown source is kept so the UI does not flip,
    /// otherwise provider order decides.
    static func select(from candidates: [NowPlaying], current: MediaSource?) -> NowPlaying? {
        let playing = candidates.filter(\.isPlaying)
        let pool = playing.isEmpty ? candidates : playing
        if let current, let sticky = pool.first(where: { $0.source == current }) {
            return sticky
        }
        return pool.first
    }
}

enum MediaTimeFormatter {
    private static let secondsPerMinute = 60
    private static let secondsPerHour = 3600

    /// "3:07", or "1:02:03" past an hour. Invalid input renders as "0:00".
    static func string(from interval: TimeInterval) -> String {
        let total = interval.isFinite ? max(Int(interval.rounded(.down)), 0) : 0
        let hours = total / secondsPerHour
        let minutes = (total % secondsPerHour) / secondsPerMinute
        let seconds = total % secondsPerMinute
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// "-1:23" time left; "--:--" when the duration is unknown (streams).
    static func remainingString(position: TimeInterval, duration: TimeInterval) -> String {
        guard duration > 0 else { return "--:--" }
        let remaining = duration - PlaybackMath.clamp(position, duration: duration)
        return "-" + string(from: remaining.rounded(.up))
    }
}
