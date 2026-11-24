/// What happens to an alert posted while notifications are muted.
enum AlertMuteBehavior: Sendable {
    /// Momentary information nobody misses afterwards (track change, network state): dropped.
    case drop
    /// Somebody wrote or something failed: held and summarized once muting ends.
    case hold
    /// Meeting reminders and finished timers: shown when the user lets them through, otherwise held.
    case timeSensitive
    /// Answers to the user's own action and security or power warnings: always shown.
    case always
}
