import AppKit

/// An app that just came to the front.
struct FocusActivation: Equatable, Sendable {
    let bundleID: String?
    let name: String?
    let processID: pid_t
}

/// Workspace side effects behind a protocol so Focus Guard logic is testable.
@MainActor
protocol FocusWorkspace: AnyObject {
    /// Delivers every app activation until `stopObserving()` is called.
    func startObserving(_ handler: @escaping @MainActor (FocusActivation) -> Void)
    func stopObserving()
    var frontmostApp: FocusActivation? { get }
    /// Brings the app back to the front; returns `false` if it is no longer running.
    @discardableResult func activate(processID: pid_t) -> Bool
}

/// `NSWorkspace.didActivateApplicationNotification` based implementation.
@MainActor
final class SystemFocusWorkspace: FocusWorkspace {
    private let center = NSWorkspace.shared.notificationCenter
    private var observer: (any NSObjectProtocol)?

    func startObserving(_ handler: @escaping @MainActor (FocusActivation) -> Void) {
        guard observer == nil else { return }
        observer = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let activation = app.map(Self.activation(for:))
            MainActor.assumeIsolated {
                guard let activation else { return }
                handler(activation)
            }
        }
    }

    func stopObserving() {
        guard let observer else { return }
        center.removeObserver(observer)
        self.observer = nil
    }

    var frontmostApp: FocusActivation? {
        NSWorkspace.shared.frontmostApplication.map(Self.activation(for:))
    }

    func activate(processID: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: processID), !app.isTerminated else { return false }
        return app.activate()
    }

    private nonisolated static func activation(for app: NSRunningApplication) -> FocusActivation {
        FocusActivation(bundleID: app.bundleIdentifier, name: app.localizedName, processID: app.processIdentifier)
    }
}
