import Foundation

/// How long alerts stay on screen, chosen under Settings › Notifications.
enum AlertDurationPreference: String, CaseIterable, Identifiable, Sendable {
    case short
    case standard
    case long

    var id: String { rawValue }

    /// Multiplier applied to every alert's own duration.
    var scale: Double {
        switch self {
        case .short: 0.6
        case .standard: 1
        case .long: 1.6
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .short: "Kısa"
        case .standard: "Normal"
        case .long: "Uzun"
        }
    }
}

/// Pure rules that keep alerts from lingering: user scale, busy-queue speed-up,
/// a cap on coalesced chains and a cap on how long hovering may hold an alert.
enum AlertTiming {
    /// Hovering pauses the countdown, but a pointer parked under the notch must not hold an alert forever.
    static let maxHoverHold: Duration = .seconds(30)
    /// Same-key re-posts (a chat burst, track changes) restart the countdown, but the chain ends after this long
    /// (or the alert's own duration, if longer).
    static let maxCoalescedLifetime: Duration = .seconds(20)
    /// Queue length from which alerts are sped up so a burst drains quickly.
    static let busyQueueThreshold = 2
    static let busyQueueScale = 0.5
    /// Neither scaling nor queue speed-up makes an alert shorter than this.
    static let minimumDuration: Duration = .seconds(3)

    /// Effective on-screen time of an alert. Pulsing (urgent / reminder) alerts ignore the busy-queue speed-up.
    static func duration(base: Duration, scale: Double, queuedCount: Int, pulses: Bool) -> Duration {
        let isBusy = !pulses && queuedCount >= busyQueueThreshold
        let factor = scale * (isBusy ? busyQueueScale : 1)
        let scaled = base * factor
        return max(scaled, min(minimumDuration, base))
    }

    /// Time left for a coalesced replacement, given when the chain started.
    static func coalescedDuration(total: Duration, elapsedInChain: Duration) -> Duration {
        let lifetime = max(maxCoalescedLifetime, total)
        let left = lifetime - elapsedInChain
        return min(total, max(left, AlertCountdown.minimumRemainingAfterResume))
    }
}
