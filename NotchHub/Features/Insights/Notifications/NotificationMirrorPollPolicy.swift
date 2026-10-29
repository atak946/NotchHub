import Foundation

/// Pace of the Notification Center safety-net poll. The AXObserver is the primary trigger, so while it is attached
/// and nothing happens the poll backs off; a banner window or a missing observer keeps it fast.
enum NotificationMirrorPollPolicy {
    /// Safety-net poll while no banner window exists.
    static let idleInterval: Duration = .seconds(1)
    /// Faster poll while Notification Center shows a banner window (fallback if AX events are missed).
    static let activeInterval: Duration = .milliseconds(250)
    /// Ceiling of the idle back-off while AX events are flowing; well under a banner's on-screen time.
    static let maxIdleInterval: Duration = .seconds(4)
    /// Quiet polls at `idleInterval` before backing off.
    static let graceCount = 5
    static let untrustedRecheckInterval: Duration = .seconds(10)

    static func delay(isTrusted: Bool, hasBannerWindow: Bool, isObserverAttached: Bool, quietPolls: Int) -> Duration {
        guard isTrusted else { return untrustedRecheckInterval }
        if hasBannerWindow { return activeInterval }
        guard isObserverAttached else { return idleInterval }
        return PowerAwareScheduler.backoff(
            base: idleInterval, maximum: maxIdleInterval, unchangedCount: quietPolls, graceCount: graceCount
        )
    }
}
