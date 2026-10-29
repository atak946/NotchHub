import Foundation
import Observation

/// Observable mirror of `ProcessInfo.isLowPowerModeEnabled` so views can stop animating in Low Power Mode.
@MainActor
@Observable
final class LowPowerModeObserver {
    /// Lives for the whole app, so its notification observer is never removed.
    static let shared = LowPowerModeObserver()

    private(set) var isLowPowerMode: Bool

    @ObservationIgnored private let read: @MainActor () -> Bool
    @ObservationIgnored private var token: (any NSObjectProtocol)?

    init(
        center: NotificationCenter = .default,
        read: @escaping @MainActor () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }
    ) {
        self.read = read
        isLowPowerMode = read()
        // The notification is posted on an arbitrary thread; hop to the main queue.
        token = center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    func refresh() {
        let value = read()
        if value != isLowPowerMode {
            isLowPowerMode = value
        }
    }
}
