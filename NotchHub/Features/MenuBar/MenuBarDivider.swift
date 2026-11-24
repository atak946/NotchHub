import AppKit

/// The two status items behind the container: the chevron the user clicks and, left of it, the divider
/// whose width pushes everything further left off screen.
@MainActor
final class MenuBarDivider {
    private static let chevronName = "NotchHubMenuBarChevron"
    private static let dividerName = "NotchHubMenuBarDivider"
    private static let hiddenLength: CGFloat = 10_000
    private static let visibleLength: CGFloat = 12
    /// Used when the system icons' place is unknown.
    private static let fallbackPosition: CGFloat = 250

    private let defaults: UserDefaults
    private let chevron: NSStatusItem
    private let divider: NSStatusItem

    var onClick: ((NSEvent) -> Void)?

    /// `position` is the distance from the right screen edge on first use; the user can ⌘-drag afterwards.
    init(position: CGFloat?, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let base = position ?? Self.fallbackPosition
        Self.setPositionIfMissing(base, for: Self.chevronName, in: defaults)
        Self.setPositionIfMissing(base + 1, for: Self.dividerName, in: defaults)
        chevron = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        chevron.autosaveName = Self.chevronName
        divider = NSStatusBar.system.statusItem(withLength: Self.visibleLength)
        divider.autosaveName = Self.dividerName
        configure()
    }

    var isHiding: Bool { divider.length == Self.hiddenLength }

    /// Cocoa screen coordinates.
    var chevronFrame: CGRect? { chevron.button?.window?.frame }
    var dividerFrame: CGRect? { divider.button?.window?.frame }

    var menuBarAppearance: NSAppearance? { chevron.button?.effectiveAppearance }

    @discardableResult
    func hide() -> Bool {
        guard let chevronFrame, let dividerFrame,
              MenuBarLayout.canHide(chevron: chevronFrame, divider: dividerFrame)
        else { return false }
        divider.length = Self.hiddenLength
        return true
    }

    func reveal() {
        divider.length = Self.visibleLength
    }

    /// Removing a status item also forgets where the user put it, so the positions are put back.
    func remove() {
        let saved = [Self.chevronName, Self.dividerName].map { ($0, defaults.object(forKey: Self.positionKey($0))) }
        NSStatusBar.system.removeStatusItem(divider)
        NSStatusBar.system.removeStatusItem(chevron)
        for (name, position) in saved {
            defaults.set(position, forKey: Self.positionKey(name))
        }
    }

    /// Forgets positions that ended up in the wrong order; the next instance starts from the default place.
    static func resetPositions(in defaults: UserDefaults = .standard) {
        [chevronName, dividerName].forEach { defaults.removeObject(forKey: positionKey($0)) }
    }

    // MARK: - Private

    private func configure() {
        chevron.button?.image = NSImage(
            systemSymbolName: "chevron.down",
            accessibilityDescription: String(localized: "Gizli menü çubuğu simgeleri")
        )
        chevron.button?.toolTip = String(localized: "Gizli menü çubuğu simgeleri")
        chevron.button?.target = self
        chevron.button?.action = #selector(didClick)
        chevron.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        divider.button?.title = "|"
        divider.button?.appearsDisabled = true
        divider.button?.setAccessibilityLabel(String(localized: "Gizli simgeler ayracı"))
    }

    @objc private func didClick() {
        guard let event = NSApp.currentEvent else { return }
        onClick?(event)
    }

    private static func positionKey(_ name: String) -> String {
        "NSStatusItem Preferred Position \(name)"
    }

    private static func setPositionIfMissing(_ position: CGFloat, for name: String, in defaults: UserDefaults) {
        guard defaults.object(forKey: positionKey(name)) == nil else { return }
        defaults.set(position, forKey: positionKey(name))
    }
}
