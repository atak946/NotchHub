import AppKit
import Observation

/// Detects displays where the frontmost app has a full-screen window.
@MainActor
@Observable
final class FullScreenDetector {
    private static let settleDelay: Duration = .milliseconds(450)

    private(set) var fullScreenDisplayIDs: Set<CGDirectDisplayID> = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
        ]
        for name in names {
            observers.append(workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        })
        refresh()
    }

    /// Space transitions animate, so check now and again once windows have settled.
    private func scheduleRefresh() {
        refresh()
        Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            self?.refresh()
        }
    }

    private func refresh() {
        let detected = Self.detect()
        if detected != fullScreenDisplayIDs {
            fullScreenDisplayIDs = detected
        }
    }

    private static func detect() -> Set<CGDirectDisplayID> {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID
              ) as? [[String: Any]]
        else { return [] }

        let windowBounds = windows.compactMap { window -> CGRect? in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
        }

        let displayIDs = NSScreen.screens.compactMap { screen -> CGDirectDisplayID? in
            guard let displayID = screen.displayID else { return nil }
            let displayBounds = CGDisplayBounds(displayID)
            let isCovered = windowBounds.contains { FullScreenMatcher.covers($0, display: displayBounds) }
            return isCovered ? displayID : nil
        }
        return Set(displayIDs)
    }
}

enum FullScreenMatcher {
    static let tolerance: CGFloat = 1

    /// Both rects use global Core Graphics coordinates (origin top-left of the primary display).
    static func covers(_ window: CGRect, display: CGRect) -> Bool {
        abs(window.minX - display.minX) <= tolerance
            && abs(window.minY - display.minY) <= tolerance
            && abs(window.width - display.width) <= tolerance
            && abs(window.height - display.height) <= tolerance
    }
}
