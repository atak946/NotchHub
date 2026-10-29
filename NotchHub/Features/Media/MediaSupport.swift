import Foundation

/// Injectable time source so position interpolation is testable.
protocol MediaClock: Sendable {
    var now: Date { get }
}

struct SystemMediaClock: MediaClock {
    var now: Date { Date() }
}

/// Small LRU cache (artwork images keyed by URL / persistent ID).
struct BoundedCache<Key: Hashable, Value> {
    let capacity: Int
    private var storage: [Key: Value] = [:]
    private var order: [Key] = []

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    var count: Int { storage.count }

    mutating func value(for key: Key) -> Value? {
        guard let value = storage[key] else { return nil }
        touch(key)
        return value
    }

    mutating func insert(_ value: Value, for key: Key) {
        storage[key] = value
        touch(key)
        while order.count > capacity {
            let evicted = order.removeFirst()
            storage[evicted] = nil
        }
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

/// Outcome of polling one provider.
enum ProviderPollResult: Sendable {
    case notRunning
    case track(NowPlaying?)
    case failed(MediaSource, ScriptError?)
}
