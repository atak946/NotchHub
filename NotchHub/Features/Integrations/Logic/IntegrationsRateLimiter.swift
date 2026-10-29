import Foundation

/// Token bucket: `capacity` requests at once, refilled continuously at `capacity / window`.
struct IntegrationsRateLimiter: Sendable {
    static let defaultCapacity = 10
    static let defaultWindow: TimeInterval = 10

    let capacity: Int
    let window: TimeInterval
    private(set) var tokens: Double
    private var lastRefill: Date?

    init(capacity: Int = Self.defaultCapacity, window: TimeInterval = Self.defaultWindow) {
        self.capacity = max(capacity, 1)
        self.window = max(window, .leastNonzeroMagnitude)
        tokens = Double(self.capacity)
    }

    private var refillPerSecond: Double { Double(capacity) / window }

    /// Consumes a token when one is available at `now`.
    mutating func allow(at now: Date) -> Bool {
        refill(at: now)
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }

    private mutating func refill(at now: Date) {
        defer { lastRefill = now }
        guard let lastRefill else { return }
        // A clock moving backwards (sleep, manual change) must not mint or burn tokens.
        let elapsed = max(now.timeIntervalSince(lastRefill), 0)
        tokens = min(tokens + elapsed * refillPerSecond, Double(capacity))
    }
}
