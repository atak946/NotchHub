import Foundation
import Synchronization
@testable import NotchHub

/// Fixed power conditions with a manual resume signal.
@MainActor
final class StaticPowerConditions: PowerConditionsProviding {
    var conditions: PowerConditions
    private var targets: [any PowerResumeTarget] = []

    init(_ conditions: PowerConditions = .nominal) {
        self.conditions = conditions
    }

    func addResumeTarget(_ target: any PowerResumeTarget) {
        targets.append(target)
    }

    func resume() {
        targets.forEach { $0.powerConditionsDidResume() }
    }
}

/// Records requested delays; each sleep blocks until cancelled so tests drive the loop with `kick()`.
final class RecordingSleeper: Sendable {
    private let storage = Mutex<[Duration]>([])

    var delays: [Duration] { storage.withLock { $0 } }

    var sleep: PowerAwareLoop.Sleeper {
        { [self] duration in
            storage.withLock { $0.append(duration) }
            try await Task.sleep(for: .seconds(3600))
        }
    }
}

@MainActor
enum EnergyTestSupport {
    /// Yields until `condition` holds or the attempts run out.
    static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            await Task.yield()
        }
    }
}
