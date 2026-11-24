import AppKit
import ApplicationServices

/// Reads every app's menu bar icons through Accessibility.
struct MenuBarItemScanner: Sendable {
    static let controlCenterBundleID = "com.apple.controlcenter"
    private static let xpcExtension = "xpc"
    private static let maxValueLength = 8
    static let messagingTimeout: Float = 0.4

    struct App: Sendable {
        let pid: pid_t
        let bundleID: String?
        let name: String
    }

    @MainActor
    static func runningApps() -> [App] {
        NSWorkspace.shared.runningApplications
            // Even background-only apps can have an icon; XPC services cannot, and there are many.
            .filter { $0.bundleURL?.pathExtension != xpcExtension }
            .map { App(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier, name: $0.localizedName ?? "") }
    }

    /// Off the main actor: an unresponsive app may take up to the messaging timeout.
    func scan(_ apps: [App]) async -> [MenuBarItem] {
        await withTaskGroup(of: [MenuBarItem].self) { group in
            for app in apps {
                group.addTask { Self.items(of: app) }
            }
            return await group.reduce(into: []) { $0 += $1 }
        }
    }

    private static func items(of app: App) -> [MenuBarItem] {
        let application = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        guard let bar = AXAttributes.element(of: application, "AXExtrasMenuBar"),
              let elements = AXAttributes.elements(of: bar, kAXChildrenAttribute)
        else { return [] }
        return elements.enumerated().compactMap { index, element in
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            guard let frame = frame(of: element), frame.width > 0 else { return nil }
            let isSystem = app.bundleID == controlCenterBundleID
            let identifier = isSystem ? AXAttributes.string(of: element, kAXIdentifierAttribute) : nil
            // Control Center also lists icons it hosts for other apps; those come from the apps themselves.
            guard !isSystem || MenuBarItem.isSystemIdentifier(identifier) else { return nil }
            let label = AXAttributes.string(of: element, kAXDescriptionAttribute)
            return MenuBarItem(
                id: "\(app.pid).\(index)",
                pid: app.pid,
                bundleID: app.bundleID,
                // Titles can hold private text (an agenda item), so only system items use their own label.
                name: isSystem ? label ?? app.name : app.name,
                value: isSystem ? nil : shortTitle(of: element),
                identifier: identifier,
                frame: frame,
                element: element
            )
        }
    }

    private static func shortTitle(of element: AXUIElement) -> String? {
        let title = AXAttributes.string(of: element, kAXTitleAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty, title.count <= maxValueLength else { return nil }
        return title
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = axValue(of: element, kAXPositionAttribute),
              let extent = axValue(of: element, kAXSizeAttribute),
              AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(extent, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func axValue(of element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = AXAttributes.value(of: element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXValue.self)
    }
}
