import Foundation

/// Machine conditions that decide how eagerly background work may run.
struct PowerConditions: Equatable, Sendable {
    var isLowPowerMode = false
    /// All displays are asleep.
    var isScreenAsleep = false
    /// The screen is locked or another user session is in front.
    var isSessionInactive = false

    static let nominal = PowerConditions()

    /// Nobody can see the notch right now.
    var isUserAway: Bool { isScreenAsleep || isSessionInactive }
}

/// How a periodic job reacts to `PowerConditions`.
enum PollingPriority: Sendable {
    /// Freshness of UI state: slowed in Low Power Mode and while the user is away.
    case standard
    /// Cadence-sensitive accounting (e.g. time tracking credits): slowed only while the user is away.
    case awayOnly
    /// Security-relevant state that must stay fresh even while away (e.g. remote sessions).
    case critical
}

/// Pure interval math shared by every poll loop: power scaling, back-off and timer tolerance.
enum PowerAwareScheduler {
    static let lowPowerMultiplier = 2.0
    static let awayMultiplier = 4.0
    /// While away, scaling never stretches an interval past this (unless the base is already longer).
    static let maxAwaySeconds = 300.0
    static let backoffFactor = 2.0
    /// Fraction of an interval the system may shift a wake-up by to coalesce it with others.
    static let toleranceFraction = 0.1
    static let maxToleranceSeconds = 5.0

    /// `base` scaled for the current conditions. Never shorter than `base`.
    static func interval(_ base: Duration, conditions: PowerConditions, priority: PollingPriority) -> Duration {
        let baseSeconds = seconds(base)
        guard baseSeconds > 0 else { return base }
        var multiplier = 1.0
        if conditions.isLowPowerMode, priority == .standard {
            multiplier *= lowPowerMultiplier
        }
        var scaled = baseSeconds * multiplier
        if conditions.isUserAway, priority != .critical {
            scaled = min(baseSeconds * multiplier * awayMultiplier, max(maxAwaySeconds, scaled))
        }
        return .seconds(max(scaled, baseSeconds))
    }

    /// Exponential back-off: `base` for the first `graceCount` unchanged polls, then doubling up to `maximum`.
    static func backoff(base: Duration, maximum: Duration, unchangedCount: Int, graceCount: Int = 0) -> Duration {
        let baseSeconds = seconds(base)
        let maxSeconds = max(seconds(maximum), baseSeconds)
        let steps = max(0, unchangedCount - max(0, graceCount))
        guard steps > 0, baseSeconds > 0 else { return base }
        // Cap the exponent so the power never overflows; maxSeconds clamps the result anyway.
        let exponent = Double(min(steps, 32))
        return .seconds(min(baseSeconds * pow(backoffFactor, exponent), maxSeconds))
    }

    /// Wake-up tolerance for an interval: 10 %, at most five seconds.
    static func tolerance(for interval: Duration) -> Duration {
        .seconds(min(max(seconds(interval), 0) * toleranceFraction, maxToleranceSeconds))
    }

    /// Sleeps `duration` with the matching tolerance so the kernel can coalesce wake-ups.
    static func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration, tolerance: tolerance(for: duration))
    }

    static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
