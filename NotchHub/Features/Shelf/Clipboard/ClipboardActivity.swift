import AppKit

/// Poll pacing: fast while the user is active, slow while the screen is locked or asleep.
enum ClipboardPollSchedule {
    static let activeInterval: Duration = .milliseconds(750)
    static let activeTolerance: Duration = .milliseconds(250)
    static let idleInterval: Duration = .seconds(3)
    static let idleTolerance: Duration = .seconds(1)

    static func interval(isIdle: Bool) -> (interval: Duration, tolerance: Duration) {
        isIdle ? (idleInterval, idleTolerance) : (activeInterval, activeTolerance)
    }
}

/// Short relative age for history tiles: "şimdi", "5 dk", "3 sa", "2 g".
enum ClipboardRelativeTime {
    static let nowText = "şimdi"
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 3600
    private static let day: TimeInterval = 86_400

    static func text(for date: Date, now: Date) -> String {
        let elapsed = max(now.timeIntervalSince(date), 0)
        if elapsed < minute { return nowText }
        if elapsed < hour { return "\(Int(elapsed / minute)) dk" }
        if elapsed < day { return "\(Int(elapsed / hour)) sa" }
        return "\(Int(elapsed / day)) g"
    }
}

/// Tracks screen lock and display / system sleep so polling can slow down.
@MainActor
final class ClipboardActivityMonitor {
    private static let lockedNotification = Notification.Name("com.apple.screenIsLocked")
    private static let unlockedNotification = Notification.Name("com.apple.screenIsUnlocked")

    private(set) var isLocked = false
    private(set) var isAsleep = false
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    var isIdle: Bool { isLocked || isAsleep }

    func start() {
        guard tokens.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Self.lockedNotification) { $0.isLocked = true }
        observe(distributed, Self.unlockedNotification) { $0.isLocked = false }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.isAsleep = true }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.isAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.isAsleep = false }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.isAsleep = false }
    }

    func stop() {
        tokens.forEach { center, token in center.removeObserver(token) }
        tokens = []
        isLocked = false
        isAsleep = false
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, update: @escaping @MainActor (ClipboardActivityMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self)
            }
        }
        tokens.append((center, token))
    }
}
