import Foundation

/// What the timer is doing at the moment an app comes to the front.
struct FocusTimerSnapshot: Equatable, Sendable {
    let state: TimerState
    let remaining: TimeInterval
    let phaseDuration: TimeInterval

    /// Seconds since the current phase started.
    var elapsed: TimeInterval { max(phaseDuration - remaining, 0) }

    var isFocusRunning: Bool { state == .running(.work) }
}

/// Outcome of evaluating one app activation.
enum FocusDecision: Equatable, Sendable {
    enum SkipReason: Equatable, Sendable {
        case notFocusing
        case notDistracting
        case gracePeriod
        case coolingDown
    }

    /// Show a reminder; `minutesLeft` is rounded up.
    case remind(minutesLeft: Int)
    case skip(SkipReason)

    var isReminder: Bool {
        if case .remind = self { return true }
        return false
    }

    /// Counts toward "distractions today": any distraction switch during focus, even while cooling down.
    var countsAsDistraction: Bool {
        switch self {
        case .remind, .skip(.coolingDown): true
        case .skip: false
        }
    }
}

/// Pure decision rules for Focus Guard: phase, grace period, per-app cooldown and list matching.
struct FocusGuardPolicy: Equatable, Sendable {
    static let defaultGracePeriod: TimeInterval = 10
    static let defaultCooldown: TimeInterval = 120
    static let cooldownOptions: [TimeInterval] = [30, 60, 120, 300, 600]

    var gracePeriod: TimeInterval = Self.defaultGracePeriod
    var cooldown: TimeInterval = Self.defaultCooldown

    func decide(
        bundleID: String?,
        timer: FocusTimerSnapshot,
        activeIDs: Set<String>,
        lastReminders: [String: Date],
        now: Date
    ) -> FocusDecision {
        guard timer.isFocusRunning else { return .skip(.notFocusing) }
        guard FocusAppList.matches(bundleID, in: activeIDs), let key = bundleID?.lowercased() else {
            return .skip(.notDistracting)
        }
        guard timer.elapsed >= gracePeriod else { return .skip(.gracePeriod) }
        if let last = lastReminders[key], now.timeIntervalSince(last) < cooldown {
            return .skip(.coolingDown)
        }
        return .remind(minutesLeft: Self.minutesLeft(timer.remaining))
    }

    static func minutesLeft(_ remaining: TimeInterval) -> Int {
        max(Int((remaining / 60).rounded(.up)), 1)
    }

    static func reminderTitle(minutesLeft: Int) -> String {
        String(localized: "Odak zamanı — \(minutesLeft) dk kaldı")
    }
}
