import AppKit
import OSLog
import SwiftUI

/// Hosts the wizard in a regular titled window. An `NSWindow` (not a SwiftUI scene) works
/// reliably for an LSUIElement app and can be opened from AppKit code at launch.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private static let windowTitle = "NotchHub Kurulumu"

    private let permissions: PermissionsModel
    private let stateStore: OnboardingStateStore
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Onboarding")
    private var window: NSWindow?
    private var activationObserver: NSObjectProtocol?

    init(permissions: PermissionsModel, stateStore: OnboardingStateStore = OnboardingStateStore()) {
        self.permissions = permissions
        self.stateStore = stateStore
    }

    /// First launch, or a newer wizard version than the user has seen.
    func showIfNeeded() {
        guard stateStore.shouldShowOnLaunch else { return }
        logger.info("Showing onboarding (stored version \(self.stateStore.completedVersion ?? 0, privacy: .public))")
        show()
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // At launch macOS may refuse to activate a background (LSUIElement) app; still bring the window forward.
        window.orderFrontRegardless()
        startLiveChecks()
    }

    func close() {
        window?.close()
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Closing early also counts as seen; the wizard stays reachable from the menu bar.
        stateStore.markCompleted()
        stopLiveChecks()
        window = nil
    }

    // MARK: Private

    private func makeWindow() -> NSWindow {
        let root = OnboardingView(permissions: permissions) { [weak self] in
            self?.close()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = Self.windowTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.setContentSize(OnboardingStyle.windowSize)
        window.center()
        window.delegate = self
        return window
    }

    private func startLiveChecks() {
        permissions.startPolling()
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let permissions = self?.permissions else { return }
                Task { await permissions.refresh() }
            }
        }
    }

    private func stopLiveChecks() {
        permissions.stopPolling()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        activationObserver = nil
    }
}
