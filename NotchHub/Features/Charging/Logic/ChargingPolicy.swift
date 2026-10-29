import Foundation

/// What the notch should present after a power change.
struct ChargingEvent: Equatable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Adapter connected, or charging (re)started while plugged in.
        case charging
        case unplugged
        case fullyCharged
        /// On battery and the level fell to `threshold` percent.
        case lowBattery(threshold: Int)

        var isWarning: Bool {
            if case .lowBattery = self { return true }
            return false
        }
    }

    let kind: Kind
    let snapshot: PowerSnapshot
}

/// Which presentations the user wants.
struct ChargingPreferences: Equatable, Sendable {
    /// "Şarj animasyonu": plug in, unplug and fully charged.
    var showsCharging: Bool
    /// "Düşük pil uyarısı".
    var warnsLowBattery: Bool
}

/// Memory of the policy between readings.
struct ChargingPolicyState: Equatable, Sendable {
    /// The last settled reading; `nil` until the first one (or on machines without a battery).
    var baseline: PowerSnapshot?
    /// "Tamamen şarj oldu" was shown (or not needed) in this plug-in session.
    var hasAnnouncedFull = false
    /// Low-battery thresholds already warned about in this discharge session.
    var warnedThresholds: Set<Int> = []
    /// When each plug/unplug presentation last appeared, to stay quiet on a flapping adapter.
    var lastShown: [ChargingEvent.Kind: Date] = [:]

    static let initial = ChargingPolicyState()
}

/// Pure decision of when to present: transitions only (never the first reading), one "full" per plug-in,
/// each low threshold once per discharge, and no repeat of the same plug/unplug presentation while flapping.
enum ChargingPolicy {
    static let lowBatteryThresholds = [20, 10]
    /// The same plug/unplug presentation is not repeated within this window.
    static let repeatCooldown: TimeInterval = 60

    struct Decision: Equatable {
        let state: ChargingPolicyState
        let event: ChargingEvent?
    }

    static func evaluate(
        _ snapshot: PowerSnapshot?,
        state: ChargingPolicyState,
        now: Date,
        preferences: ChargingPreferences
    ) -> Decision {
        // No battery (desktop) or it vanished: forget everything, show nothing.
        guard let snapshot else { return Decision(state: .initial, event: nil) }
        guard let previous = state.baseline else {
            return Decision(state: baselineState(for: snapshot, lastShown: state.lastShown), event: nil)
        }
        let transition = transition(from: previous, to: snapshot, state: state)
        guard let event = transition.event, isWanted(event.kind, preferences: preferences) else {
            return Decision(state: transition.state, event: nil)
        }
        if isCoolingDown(event.kind, lastShown: transition.state.lastShown, now: now) {
            return Decision(state: transition.state, event: nil)
        }
        var next = transition.state
        if usesCooldown(event.kind) {
            next.lastShown[event.kind] = now
        }
        return Decision(state: next, event: event)
    }

    // MARK: - Private

    private static func baselineState(for snapshot: PowerSnapshot, lastShown: [ChargingEvent.Kind: Date]) -> ChargingPolicyState {
        ChargingPolicyState(
            baseline: snapshot,
            hasAnnouncedFull: snapshot.isPluggedIn && snapshot.isFull,
            warnedThresholds: snapshot.isPluggedIn ? [] : reachedThresholds(at: snapshot.percent),
            lastShown: lastShown
        )
    }

    private static func transition(
        from previous: PowerSnapshot,
        to snapshot: PowerSnapshot,
        state: ChargingPolicyState
    ) -> Decision {
        var next = state
        next.baseline = snapshot

        if !previous.isPluggedIn, snapshot.isPluggedIn {
            next.warnedThresholds = []
            // Plugging in an already full battery says so in the plug-in presentation itself.
            next.hasAnnouncedFull = snapshot.isFull
            return Decision(state: next, event: ChargingEvent(kind: .charging, snapshot: snapshot))
        }
        if previous.isPluggedIn, !snapshot.isPluggedIn {
            next.hasAnnouncedFull = false
            // Unplugging at 15 % must not warn about 20 % later; 10 % still warns.
            next.warnedThresholds = reachedThresholds(at: snapshot.percent)
            return Decision(state: next, event: ChargingEvent(kind: .unplugged, snapshot: snapshot))
        }
        if snapshot.isPluggedIn {
            return pluggedTransition(from: previous, to: snapshot, state: next)
        }
        return dischargeTransition(from: previous, to: snapshot, state: next)
    }

    private static func pluggedTransition(
        from previous: PowerSnapshot,
        to snapshot: PowerSnapshot,
        state: ChargingPolicyState
    ) -> Decision {
        var next = state
        if !previous.isCharging, snapshot.isCharging {
            return Decision(state: next, event: ChargingEvent(kind: .charging, snapshot: snapshot))
        }
        guard snapshot.isFull, !next.hasAnnouncedFull else { return Decision(state: next, event: nil) }
        next.hasAnnouncedFull = true
        return Decision(state: next, event: ChargingEvent(kind: .fullyCharged, snapshot: snapshot))
    }

    private static func dischargeTransition(
        from previous: PowerSnapshot,
        to snapshot: PowerSnapshot,
        state: ChargingPolicyState
    ) -> Decision {
        var next = state
        let crossed = lowBatteryThresholds.filter { threshold in
            previous.percent > threshold
                && snapshot.percent <= threshold
                && !state.warnedThresholds.contains(threshold)
        }
        next.warnedThresholds = state.warnedThresholds.union(reachedThresholds(at: snapshot.percent))
        // Several thresholds at once (e.g. after sleep): only the most urgent one is shown.
        guard let threshold = crossed.min() else { return Decision(state: next, event: nil) }
        return Decision(state: next, event: ChargingEvent(kind: .lowBattery(threshold: threshold), snapshot: snapshot))
    }

    private static func reachedThresholds(at percent: Int) -> Set<Int> {
        Set(lowBatteryThresholds.filter { percent <= $0 })
    }

    private static func isWanted(_ kind: ChargingEvent.Kind, preferences: ChargingPreferences) -> Bool {
        switch kind {
        case .charging, .unplugged, .fullyCharged: preferences.showsCharging
        case .lowBattery: preferences.warnsLowBattery
        }
    }

    private static func usesCooldown(_ kind: ChargingEvent.Kind) -> Bool {
        kind == .charging || kind == .unplugged
    }

    private static func isCoolingDown(_ kind: ChargingEvent.Kind, lastShown: [ChargingEvent.Kind: Date], now: Date) -> Bool {
        guard usesCooldown(kind), let last = lastShown[kind] else { return false }
        return now.timeIntervalSince(last) < repeatCooldown
    }
}
