import Foundation

/// Commits a new value only after it has been observed continuously for `holdInterval`.
/// The very first observation commits immediately so monitors have a baseline without alerting.
struct SystemDebouncer<Value: Equatable> {
    let holdInterval: TimeInterval
    private(set) var stable: Value?
    private(set) var pending: Value?
    private(set) var pendingSince: Date?

    init(holdInterval: TimeInterval) {
        self.holdInterval = holdInterval
    }

    /// When the pending value will be committed if nothing else changes.
    var settleDate: Date? {
        pendingSince?.addingTimeInterval(holdInterval)
    }

    /// Feeds a sample. Returns the value when it becomes the new stable value.
    mutating func observe(_ value: Value, at date: Date) -> Value? {
        guard let current = stable else {
            stable = value
            clearPending()
            return value
        }
        if value == current {
            clearPending()
            return nil
        }
        if value != pending {
            pending = value
            pendingSince = date
        }
        return settle(at: date)
    }

    /// Commits the pending value once it has been held long enough.
    mutating func settle(at date: Date) -> Value? {
        guard let candidate = pending, let since = pendingSince,
              date.timeIntervalSince(since) >= holdInterval
        else { return nil }
        stable = candidate
        clearPending()
        return candidate
    }

    mutating func reset() {
        stable = nil
        clearPending()
    }

    private mutating func clearPending() {
        pending = nil
        pendingSince = nil
    }
}
