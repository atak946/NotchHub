import AppKit
import ApplicationServices

/// Reads badge text from Dock items. Requires Accessibility trust.
protocol DockBadgeReading: Sendable {
    /// Dock item name → unread count, or `nil` when the Dock could not be read. Each item is keyed by its
    /// (localized) title and by its bundle file name, so "Messages" matches "Mesajlar" on a Turkish system.
    func readBadges() -> [String: Int]?
}

/// Walks `com.apple.dock` → AXList → dock items, reading `AXTitle` and `AXStatusLabel`.
struct AXDockBadgeReader: DockBadgeReading {
    static let dockBundleID = "com.apple.dock"
    static let statusLabelAttribute = "AXStatusLabel"
    /// Seconds an AX call may block before giving up (the Dock answers in milliseconds normally).
    static let messagingTimeout: Float = 0.5

    func readBadges() -> [String: Int]? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: Self.dockBundleID).first
        else { return nil }
        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(dockElement, Self.messagingTimeout)
        guard let children = AXAttributes.elements(of: dockElement, kAXChildrenAttribute) else { return nil }

        var badges: [String: Int] = [:]
        let lists = children.filter { AXAttributes.string(of: $0, kAXRoleAttribute) == kAXListRole }
        for list in lists {
            for item in AXAttributes.elements(of: list, kAXChildrenAttribute) ?? [] {
                let count = BadgeTextParser.count(from: AXAttributes.string(of: item, Self.statusLabelAttribute))
                for name in Self.names(of: item) {
                    badges[name] = max(badges[name] ?? 0, count)
                }
            }
        }
        return badges
    }

    private static func names(of item: AXUIElement) -> [String] {
        let title = AXAttributes.string(of: item, kAXTitleAttribute)
        let fileName = (AXAttributes.value(of: item, kAXURLAttribute) as? URL).map(appName(fromBundleURL:))
        return [title, fileName].compactMap { $0 }.filter { !$0.isEmpty }
    }

    /// "/System/Applications/Messages.app/" → "Messages".
    static func appName(fromBundleURL url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }
}

/// Small typed helpers over `AXUIElementCopyAttributeValue`.
enum AXAttributes {
    static func value(of element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return error == .success ? value : nil
    }

    static func string(of element: AXUIElement, _ attribute: String) -> String? {
        value(of: element, attribute) as? String
    }

    static func element(of element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(of: element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func elements(of element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        value(of: element, attribute) as? [AXUIElement]
    }
}
