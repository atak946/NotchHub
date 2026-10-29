import AppKit
import ApplicationServices

/// Reads and dismisses macOS notification banners. Requires Accessibility trust.
protocol NotificationBannerReading: Sendable {
    /// `nil` when Notification Center could not be read (process missing, AX failure).
    func readSnapshot() -> NotificationCenterSnapshot?
    /// Closes the on-screen banner with that id; `false` when it is gone or offers no close control.
    func dismiss(bannerID: String) -> Bool
}

/// Walks `com.apple.notificationcenterui` → AXSystemDialog window → every AXNotificationCenterBanner.
/// Desktop widget windows of the same process are skipped by subrole.
struct AXNotificationBannerReader: NotificationBannerReading {
    static let bundleID = "com.apple.notificationcenterui"
    static let bannerWindowSubrole = "AXSystemDialog"
    static let bannerSubrole = "AXNotificationCenterBanner"
    static let identifierAttribute = "AXIdentifier"
    static let closeButtonIdentifier = "xmark"
    /// Banners sit about five levels below the window; groups and stacks add a few more.
    static let maxDepth = 10
    /// Field and close-button children are direct children of the banner, sometimes one group deeper.
    static let fieldDepth = 3
    static let messagingTimeout: Float = 0.25

    private enum Field {
        static let title = "title"
        static let subtitle = "subtitle"
        static let body = "body"
    }

    func readSnapshot() -> NotificationCenterSnapshot? {
        guard let windows = bannerWindows() else { return nil }
        let banners = windows
            .flatMap { Self.bannerElements(in: $0) }
            .compactMap { NotificationBannerParser.banner(from: Self.raw(from: $0)) }
        return NotificationCenterSnapshot(banners: banners, hasBannerWindow: !windows.isEmpty)
    }

    func dismiss(bannerID: String) -> Bool {
        guard let windows = bannerWindows() else { return false }
        let banner = windows.flatMap { Self.bannerElements(in: $0) }.first {
            AXAttributes.string(of: $0, Self.identifierAttribute) == bannerID
        }
        guard let banner else { return false }
        if let button = Self.descendant(of: banner, depth: Self.fieldDepth, where: {
            AXAttributes.string(of: $0, Self.identifierAttribute) == Self.closeButtonIdentifier
        }), AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
            return true
        }
        var names: CFArray?
        guard AXUIElementCopyActionNames(banner, &names) == .success,
              let action = NotificationBannerParser.closeActionName(from: names as? [String] ?? [])
        else { return false }
        return AXUIElementPerformAction(banner, action as CFString) == .success
    }

    // MARK: - Private

    /// `nil` when the process or its window list is unavailable; empty when no banner is on screen.
    private func bannerWindows() -> [AXUIElement]? {
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first
        else { return nil }
        let app = AXUIElementCreateApplication(process.processIdentifier)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        guard let windows = AXAttributes.elements(of: app, kAXWindowsAttribute) else { return nil }
        return windows.filter { AXAttributes.string(of: $0, kAXSubroleAttribute) == Self.bannerWindowSubrole }
    }

    private static func bannerElements(in root: AXUIElement) -> [AXUIElement] {
        var found: [AXUIElement] = []
        collect(root, depth: 0, into: &found)
        return found
    }

    private static func collect(_ element: AXUIElement, depth: Int, into found: inout [AXUIElement]) {
        if AXAttributes.string(of: element, kAXSubroleAttribute) == bannerSubrole {
            found.append(element)
        }
        guard depth < maxDepth else { return }
        for child in AXAttributes.elements(of: element, kAXChildrenAttribute) ?? [] {
            collect(child, depth: depth + 1, into: &found)
        }
    }

    private static func raw(from banner: AXUIElement) -> RawNotificationBanner {
        var raw = RawNotificationBanner(
            identifier: AXAttributes.string(of: banner, identifierAttribute),
            description: AXAttributes.string(of: banner, kAXDescriptionAttribute)
        )
        for child in fieldElements(of: banner, depth: fieldDepth) {
            let value = AXAttributes.string(of: child, kAXValueAttribute)
            switch AXAttributes.string(of: child, identifierAttribute) {
            case Field.title: raw.title = value
            case Field.subtitle: raw.subtitle = value
            case Field.body: raw.body = value
            default: break
            }
        }
        return raw
    }

    /// Descendants up to `depth`, never entering a nested banner (its fields belong to it).
    private static func fieldElements(of element: AXUIElement, depth: Int) -> [AXUIElement] {
        guard depth > 0 else { return [] }
        let children = (AXAttributes.elements(of: element, kAXChildrenAttribute) ?? [])
            .filter { AXAttributes.string(of: $0, kAXSubroleAttribute) != bannerSubrole }
        return children + children.flatMap { fieldElements(of: $0, depth: depth - 1) }
    }

    private static func descendant(
        of element: AXUIElement, depth: Int, where matches: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        fieldElements(of: element, depth: depth).first(where: matches)
    }
}
