import AppKit
import Foundation

/// Something that wants to refresh right away when the user comes back (screen wake, unlock, Low Power Mode off).
@MainActor
protocol PowerResumeTarget: AnyObject {
    func powerConditionsDidResume()
}

/// Current power conditions plus a resume signal, injectable for tests.
@MainActor
protocol PowerConditionsProviding: AnyObject {
    var conditions: PowerConditions { get }
    /// Held weakly; a deallocated target is dropped silently.
    func addResumeTarget(_ target: any PowerResumeTarget)
}

/// Live conditions from NSWorkspace (display sleep, session switch), screen-lock distributed
/// notifications and `ProcessInfo.isLowPowerModeEnabled`.
@MainActor
final class PowerConditionsMonitor: PowerConditionsProviding {
    static let shared = PowerConditionsMonitor()

    private static let screenLocked = Notification.Name("com.apple.screenIsLocked")
    private static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")

    private struct WeakTarget {
        weak var target: (any PowerResumeTarget)?
    }

    private(set) var conditions: PowerConditions
    private var targets: [WeakTarget] = []
    private var tokens: [(NotificationCenter, any NSObjectProtocol)] = []

    private init() {
        conditions = PowerConditions(isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
        observe()
    }

    func addResumeTarget(_ target: any PowerResumeTarget) {
        targets = targets.filter { $0.target != nil && $0.target !== target } + [WeakTarget(target: target)]
    }

    // MARK: - Private

    private func observe() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        add(workspace, NSWorkspace.screensDidSleepNotification) { $0.isScreenAsleep = true }
        add(workspace, NSWorkspace.screensDidWakeNotification) { $0.isScreenAsleep = false }
        add(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.isSessionInactive = true }
        add(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.isSessionInactive = false }
        add(workspace, NSWorkspace.didWakeNotification) { $0.isScreenAsleep = false }
        add(distributed, Self.screenLocked) { $0.isSessionInactive = true }
        add(distributed, Self.screenUnlocked) { $0.isSessionInactive = false }
        add(.default, .NSProcessInfoPowerStateDidChange) {
            $0.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func add(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ change: @escaping @MainActor (inout PowerConditions) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.update(change)
            }
        }
        tokens.append((center, token))
    }

    private func update(_ change: (inout PowerConditions) -> Void) {
        var next = conditions
        change(&next)
        guard next != conditions else { return }
        let resumed = PowerConditionsTransition.isResume(from: conditions, to: next)
        conditions = next
        guard resumed else { return }
        targets = targets.filter { $0.target != nil }
        targets.forEach { $0.target?.powerConditionsDidResume() }
    }
}

/// Decides when a condition change should make loops refresh immediately.
enum PowerConditionsTransition {
    /// The user came back, or Low Power Mode was switched off.
    static func isResume(from old: PowerConditions, to new: PowerConditions) -> Bool {
        let cameBack = old.isUserAway && !new.isUserAway
        let leftLowPower = old.isLowPowerMode && !new.isLowPowerMode
        return cameBack || leftLowPower
    }
}
