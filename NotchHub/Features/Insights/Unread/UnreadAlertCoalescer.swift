import Foundation

/// A watched app whose unread count went up between two polls.
struct UnreadIncrease: Equatable, Sendable {
    let app: String
    /// Unread count right now.
    let count: Int
    /// New messages since the start of the current alert burst.
    let newMessages: Int
}

/// Decides which unread changes deserve an alert. Increases inside `window` of the previous alert
/// for the same app are folded into one growing burst ("3 new" instead of three "1 new" alerts).
struct UnreadAlertCoalescer: Sendable {
    static let window: TimeInterval = 4

    private struct Burst: Sendable {
        let baseline: Int
        let lastAlertAt: Date
    }

    private var bursts: [String: Burst] = [:]

    /// `previous == nil` means "no baseline yet" (first poll, permission just granted): never alert.
    mutating func evaluate(previous: [String: Int]?, current: [String: Int], at now: Date) -> [UnreadIncrease] {
        guard let previous else {
            bursts = [:]
            return []
        }
        var increases: [UnreadIncrease] = []
        for app in current.keys.sorted() {
            let old = previous[app] ?? 0
            let new = current[app] ?? 0
            if new < old {
                bursts[app] = nil
            }
            guard new > old else { continue }
            let baseline = activeBurst(for: app, at: now)?.baseline ?? old
            bursts[app] = Burst(baseline: baseline, lastAlertAt: now)
            increases.append(UnreadIncrease(app: app, count: new, newMessages: new - baseline))
        }
        return increases
    }

    private func activeBurst(for app: String, at now: Date) -> Burst? {
        guard let burst = bursts[app], now.timeIntervalSince(burst.lastAlertAt) < Self.window else { return nil }
        return burst
    }
}
