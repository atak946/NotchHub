import AppKit
import ApplicationServices
import OSLog

/// Push signal that Notification Center's UI changed, so a new banner is read within ~0.3 s instead of
/// waiting for the next poll. Polling stays as the safety net.
@MainActor
protocol NotificationCenterEventObserving: AnyObject {
    /// Idempotent; re-attaches when Notification Center was relaunched with a new pid.
    func attach(onEvent: @escaping @MainActor () -> Void)
    func detach()
    /// True while push events are expected, so the safety-net poll may back off.
    var isAttached: Bool { get }
}

extension NotificationCenterEventObserving {
    var isAttached: Bool { false }
}

/// AXObserver on `com.apple.notificationcenterui` for window/element creation and layout changes.
@MainActor
final class AXNotificationCenterObserver: NotificationCenterEventObserving {
    static let notifications = [
        kAXWindowCreatedNotification,
        kAXCreatedNotification,
        kAXLayoutChangedNotification,
    ]

    /// Holds the handler for the C callback; only ever touched on the main run loop.
    private final class Handler {
        let onEvent: @MainActor () -> Void

        init(onEvent: @escaping @MainActor () -> Void) {
            self.onEvent = onEvent
        }
    }

    private var observer: AXObserver?
    private var observedPID: pid_t?

    var isAttached: Bool { observer != nil }
    private var handler: Handler?
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Insights")

    func attach(onEvent: @escaping @MainActor () -> Void) {
        guard let process = NSRunningApplication
            .runningApplications(withBundleIdentifier: AXNotificationBannerReader.bundleID).first
        else {
            detach()
            return
        }
        let pid = process.processIdentifier
        guard observer == nil || observedPID != pid else { return }
        detach()

        var created: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &created) == .success, let created else {
            logger.debug("AXObserver for Notification Center unavailable")
            return
        }
        let handler = Handler(onEvent: onEvent)
        let refcon = Unmanaged.passUnretained(handler).toOpaque()
        let app = AXUIElementCreateApplication(pid)
        let added = Self.notifications.filter {
            AXObserverAddNotification(created, app, $0 as CFString, refcon) == .success
        }
        guard !added.isEmpty else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        observedPID = pid
        self.handler = handler
    }

    func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedPID = nil
        handler = nil
    }

    /// The run loop source lives on the main run loop, so callbacks arrive on the main thread.
    private static let callback: AXObserverCallback = { _, _, _, refcon in
        // Pass the address as an integer: raw pointers are not Sendable into the isolated closure.
        guard let refcon else { return }
        let address = UInt(bitPattern: refcon)
        MainActor.assumeIsolated {
            guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
            Unmanaged<Handler>.fromOpaque(pointer).takeUnretainedValue().onEvent()
        }
    }
}
