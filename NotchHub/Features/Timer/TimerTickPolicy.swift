import Foundation

/// When the running timer next needs a UI refresh: exactly when the visible text changes, or when the
/// progress ring has moved by one small step. The closed-notch glyph shows "13dk" / "1sa" above ten minutes,
/// so it does not need per-second ticks then.
enum TimerTickPolicy {
    /// Lands just past the boundary so `TimerFormatter` (which rounds up) already shows the new value.
    static let boundaryMargin: TimeInterval = 0.02
    /// The ring is redrawn at least this many times per phase (about 0.35 pt per step on the closed glyph).
    static let ringSteps = 200.0
    static let minRingStep: TimeInterval = 1
    static let maxRingStep: TimeInterval = 60

    private static let secondsPerMinute = 60
    private static let secondsPerHour = 3600
    /// Mirrors `TimerFormatter.compactSecondsThreshold`.
    private static let compactSecondsThreshold = 600

    static func delay(remaining: TimeInterval, phaseDuration: TimeInterval, showsSeconds: Bool) -> TimeInterval {
        guard remaining.isFinite, remaining > 0 else { return minRingStep }
        let shown = Int(remaining.rounded(.up))
        let nextShown = showsSeconds ? shown - 1 : nextCompactChange(fromShown: shown)
        let textDelay = remaining - TimeInterval(max(nextShown, 0)) + boundaryMargin
        let ringStep = min(max(phaseDuration / ringSteps, minRingStep), maxRingStep)
        return max(min(textDelay, ringStep), boundaryMargin)
    }

    /// The largest whole-second remaining value whose compact text differs from the one at `shown`.
    static func nextCompactChange(fromShown shown: Int) -> Int {
        if shown >= secondsPerHour {
            return (shown / secondsPerHour) * secondsPerHour - 1
        }
        if shown >= compactSecondsThreshold {
            let minutes = (shown + secondsPerMinute - 1) / secondsPerMinute
            return max((minutes - 1) * secondsPerMinute, compactSecondsThreshold - 1)
        }
        return shown - 1
    }
}
