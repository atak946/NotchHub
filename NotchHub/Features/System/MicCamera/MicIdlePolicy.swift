import Foundation

/// When to warn that the microphone has been on for a long time outside of a meeting.
enum MicIdlePolicy {
    static func shouldAlert(
        activeSince: Date?,
        now: Date,
        threshold: TimeInterval,
        isMeetingAppRunning: Bool,
        alreadyAlerted: Bool
    ) -> Bool {
        guard threshold > 0, let activeSince, !alreadyAlerted, !isMeetingAppRunning else { return false }
        return now.timeIntervalSince(activeSince) >= threshold
    }
}
