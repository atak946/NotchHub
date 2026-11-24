import AppKit
import ApplicationServices
import OSLog

/// Presses a menu bar icon and brings the window it opens below the chevron.
struct MenuBarItemActivator: Sendable {
    enum Outcome: Sendable {
        /// A window opened and was moved below the chevron.
        case movedWindow
        /// The icon's menu opened; only its app can place it.
        case menu
        /// A window opened where it can be seen, or an ordinary one the app placed itself.
        case visible
        /// A window opened off screen and cannot be moved.
        case stuck
        case nothingOpened
    }

    private static let pollInterval: Duration = .milliseconds(20)
    private static let onScreenTimeout: Duration = .seconds(1.5)
    private static let closeTimeout: Duration = .milliseconds(600)
    private static let elementTimeout: Duration = .milliseconds(500)
    private static let minVisibleAlpha = 0.05
    /// Window number fields of a mouse event; the last one has no name in the SDK.
    private static let windowFields: [CGEventField] = [
        .mouseEventWindowUnderMousePointer, .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
    ] + [CGEventField(rawValue: 0x33)].compactMap { $0 }
    private static let clickDuration: Duration = .milliseconds(40)
    private static let windowTolerance: CGFloat = 4
    private static let gap: CGFloat = 6

    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "MenuBar")

    func hasMenu(_ item: MenuBarItem) async -> Bool {
        !Self.menus(of: item).isEmpty
    }

    /// The icon slides back after the divider collapses; a menu opened too early would hang off screen.
    func waitUntilOnScreen(_ item: MenuBarItem, screens: [CGRect]) async -> Bool {
        await poll(for: Self.onScreenTimeout) {
            MenuBarItemScanner.frame(of: item.element).map { MenuBarLayout.isOnScreen($0, screens: screens) } ?? false
        }
    }

    func openWindows(of item: MenuBarItem) -> Set<CGWindowID> {
        Set(Self.windows(of: item.pid).map(\.id))
    }

    /// Returns at once; an open menu keeps the call busy until it times out or the menu closes.
    static func pressInBackground(_ element: AXUIElement) {
        let box = UncheckedElement(element: element)
        Task.detached {
            let error = AXUIElementPerformAction(box.element, kAXPressAction as CFString)
            if error != .success, error != .cannotComplete {
                logger.error("Pressing a menu bar item failed: \(error.rawValue, privacy: .public)")
            }
        }
    }

    /// Closes the menu a press opened, and waits until it is gone.
    func cancelMenu(of item: MenuBarItem, notIn before: Set<CGWindowID>) async {
        for menu in Self.menus(of: item) {
            AXUIElementPerformAction(menu, kAXCancelAction as CFString)
        }
        _ = await poll(for: Self.closeTimeout) {
            !Self.windows(of: item.pid).contains { !before.contains($0.id) }
        }
    }

    /// Clicks the icon where it is, hidden or not, without touching the pointer: Control Center hosts every
    /// icon and passes a click on its window to the icon's app. False when that window is not found.
    /// It drops right clicks, so a secondary click is sent as the ⌃-click apps treat alike.
    func click(_ item: MenuBarItem, button: CGMouseButton) async -> Bool {
        guard let itemFrame = MenuBarItemScanner.frame(of: item.element),
              let window = MenuBarHostWindow.all().first(where: { $0.hosts(itemFrame) })
        else {
            Self.logger.error("No menu bar window found for an icon")
            return false
        }
        let point = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            else { return false }
            event.flags = button == .right ? .maskControl : []
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(window.ownerPID))
            for field in Self.windowFields {
                event.setIntegerValueField(field, value: Int64(window.id))
            }
            event.postToPid(window.ownerPID)
            // Never leave the button down, even when cancelled in between.
            try? await Task.sleep(for: Self.clickDuration)
        }
        return true
    }

    func waitForWindow(of item: MenuBarItem, notIn before: Set<CGWindowID>, timeout: Duration) async -> Bool {
        await poll(for: timeout) { Self.windows(of: item.pid).contains { !before.contains($0.id) } }
    }

    /// Moves the new window below `anchor`, inside `screen` (both top-left based).
    func settle(
        _ item: MenuBarItem, notIn before: Set<CGWindowID>, anchor: CGRect, screen: CGRect, timeout: Duration
    ) async -> Outcome {
        guard await waitForWindow(of: item, notIn: before, timeout: timeout),
              let window = Self.windows(of: item.pid).first(where: { !before.contains($0.id) })
        else { return .nothingOpened }
        // An ordinary window (layer 0) belongs where the app put it.
        guard window.layer > 0 else { return .visible }
        if Self.menus(of: item).contains(where: { Self.isSamePlace(MenuBarItemScanner.frame(of: $0), window.frame) }) {
            return .menu
        }
        guard let element = await movableElement(of: window, pid: item.pid) else {
            return window.frame.intersects(screen) ? .visible : .stuck
        }
        let x = min(max(anchor.midX - window.frame.width / 2, screen.minX), max(screen.minX, screen.maxX - window.frame.width))
        var origin = CGPoint(x: x, y: anchor.maxY + Self.gap)
        guard let value = AXValueCreate(.cgPoint, &origin),
              AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
        else { return .stuck }
        return .movedWindow
    }

    // MARK: - Private

    private struct Window {
        let id: CGWindowID
        let layer: Int
        let frame: CGRect
    }

    private struct UncheckedElement: @unchecked Sendable {
        let element: AXUIElement
    }

    private static func menus(of item: MenuBarItem) -> [AXUIElement] {
        (AXAttributes.elements(of: item.element, kAXChildrenAttribute) ?? [])
            .filter { AXAttributes.string(of: $0, kAXRoleAttribute) == kAXMenuRole }
    }

    private static func isSamePlace(_ lhs: CGRect?, _ rhs: CGRect) -> Bool {
        guard let lhs else { return false }
        return abs(lhs.minX - rhs.minX) < windowTolerance && abs(lhs.minY - rhs.minY) < windowTolerance
    }

    /// Accessibility lists a new window a little later than the window server.
    private func movableElement(of window: Window, pid: pid_t) async -> AXUIElement? {
        let deadline = ContinuousClock.now + Self.elementTimeout
        while !Task.isCancelled, ContinuousClock.now < deadline {
            // The window may still be animating into place, so match its current frame.
            guard let current = Self.windows(of: pid).first(where: { $0.id == window.id }) else { return nil }
            if let element = Self.element(of: current, pid: pid) { return element }
            try? await Task.sleep(for: Self.pollInterval)
        }
        return nil
    }

    private func poll(for timeout: Duration, until condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !Task.isCancelled {
            if condition() { return true }
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: Self.pollInterval)
        }
        return false
    }

    /// The Accessibility window behind a window server window, when the app lets others move it.
    private static func element(of window: Window, pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, MenuBarItemScanner.messagingTimeout)
        return AXAttributes.elements(of: app, kAXWindowsAttribute)?.first { element in
            guard isSamePlace(MenuBarItemScanner.frame(of: element), window.frame) else { return false }
            var isSettable: DarwinBoolean = false
            let error = AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &isSettable)
            return error == .success && isSettable.boolValue
        }
    }

    private static func windows(of pid: pid_t) -> [Window] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  // Some apps keep a closed window around, transparent or empty.
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > minVisibleAlpha,
                  frame.width > 1, frame.height > 1
            else { return nil }
            return Window(id: id, layer: info[kCGWindowLayer as String] as? Int ?? 0, frame: frame)
        }
    }
}
