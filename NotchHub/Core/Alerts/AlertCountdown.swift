import Foundation

/// Auto-dismiss countdown of the current alert. Pausing (hover) keeps the remaining time instead of resetting it.
struct AlertCountdown: Equatable, Sendable {
    typealias Instant = ContinuousClock.Instant

    /// After a hover the alert stays at least this long, so it never vanishes right as the pointer leaves.
    static let minimumRemainingAfterResume: Duration = .seconds(2)

    let total: Duration
    /// Time left when the countdown was last paused or resumed.
    let remaining: Duration
    /// `nil` while paused.
    let resumedAt: Instant?

    static func started(total: Duration, at now: Instant) -> AlertCountdown {
        AlertCountdown(total: total, remaining: total, resumedAt: now)
    }

    var isRunning: Bool { resumedAt != nil }

    func remaining(at now: Instant) -> Duration {
        guard let resumedAt else { return remaining }
        let left = remaining - resumedAt.duration(to: now)
        return max(left, .zero)
    }

    /// 1 when just started, 0 when the alert is about to auto-dismiss.
    func fraction(at now: Instant) -> Double {
        guard total > .zero else { return 0 }
        let value = remaining(at: now) / total
        return min(max(value, 0), 1)
    }

    func paused(at now: Instant) -> AlertCountdown {
        guard isRunning else { return self }
        return AlertCountdown(total: total, remaining: remaining(at: now), resumedAt: nil)
    }

    func resumed(at now: Instant) -> AlertCountdown {
        guard !isRunning else { return self }
        let floor = min(Self.minimumRemainingAfterResume, total)
        return AlertCountdown(total: total, remaining: max(remaining, floor), resumedAt: now)
    }
}
