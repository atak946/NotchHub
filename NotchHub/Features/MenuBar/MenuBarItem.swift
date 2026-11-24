import ApplicationServices
import CoreGraphics

/// One icon in the menu bar, as reported by its app through Accessibility.
struct MenuBarItem: Identifiable, @unchecked Sendable {
    /// Stable while the app runs: its pid and the item's position among the app's own items.
    let id: String
    let pid: pid_t
    let bundleID: String?
    let name: String
    /// Short text the icon shows ("● 3"); longer titles may be private and do not fit.
    let value: String?
    /// System items only ("com.apple.menuextra.wifi"); picks their symbol.
    let identifier: String?
    /// Top-left based screen coordinates.
    let frame: CGRect
    /// AXUIElement is an immutable reference that is safe to message from any thread.
    let element: AXUIElement

    /// Symbol for system items, which all belong to Control Center and would share its icon.
    var systemSymbol: String? {
        identifier.flatMap { Self.systemSymbols[$0] }
    }

    private static let systemSymbols = [
        "com.apple.menuextra.wifi": "wifi",
        "com.apple.menuextra.bluetooth": "wave.3.right",
        "com.apple.menuextra.battery": "battery.100percent",
        "com.apple.menuextra.sound": "speaker.wave.2.fill",
        "com.apple.menuextra.display": "sun.max.fill",
        "com.apple.menuextra.focusmode": "moon.fill",
        "com.apple.menuextra.now-playing": "play.circle.fill",
        "com.apple.menuextra.screen-mirroring": "rectangle.on.rectangle",
        "com.apple.menuextra.airdrop": "dot.radiowaves.left.and.right",
        "com.apple.menuextra.user": "person.crop.circle",
        "com.apple.menuextra.controlcenter": "switch.2",
        "com.apple.menuextra.clock": "clock",
    ]
}

/// Pure geometry: which items sit behind the divider.
enum MenuBarLayout {
    /// Items on the same menu bar differ by a few points of padding only.
    private static let rowTolerance: CGFloat = 20

    /// Items left of the divider on the divider's menu bar, in menu bar order.
    static func hiddenItems(in items: [MenuBarItem], divider: CGRect) -> [MenuBarItem] {
        items
            .filter { abs($0.frame.midY - divider.midY) < rowTolerance && $0.frame.midX < divider.minX }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// The chevron has to stay right of the divider, or hiding would push it off screen too.
    static func canHide(chevron: CGRect, divider: CGRect) -> Bool {
        chevron.midX > divider.midX
    }

    /// True when the item is fully on one of the screens' menu bars.
    static func isOnScreen(_ frame: CGRect, screens: [CGRect]) -> Bool {
        !frame.isEmpty && screens.contains { $0.minX <= frame.minX && frame.maxX <= $0.maxX && abs($0.minY - frame.minY) < rowTolerance }
    }

    /// Distance from the right edge where new items should go: just left of the leftmost system item.
    static func preferredPosition(systemItems: [CGRect], screens: [CGRect]) -> CGFloat? {
        guard let leftmost = systemItems.min(by: { $0.minX < $1.minX }),
              let screen = screens.first(where: { $0.contains(CGPoint(x: leftmost.midX, y: leftmost.midY)) })
        else { return nil }
        return screen.maxX - leftmost.minX
    }
}
