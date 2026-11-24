import AppKit

/// "Bildirimleri Sustur" submenu of the app menu: mute lengths, state and what arrived meanwhile.
@MainActor
final class MuteMenuBuilder: NSObject {
    private static let maxListedAlerts = 10
    private static let maxTitleLength = 60

    private let mute: AlertMuteService

    init(mute: AlertMuteService) {
        self.mute = mute
    }

    func makeItem() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "Bildirimleri Sustur"), action: nil, keyEquivalent: "")
        item.state = mute.isMuted ? .on : .off
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        addState(to: submenu)
        addHeld(to: submenu)
        item.submenu = submenu
        return item
    }

    private func addState(to menu: NSMenu) {
        if let reason = mute.reason {
            addLabel(reason.title, to: menu)
            add(String(localized: "Susturmayı kapat"), to: menu, action: #selector(unmute))
            menu.addItem(.separator())
        }
        for (index, duration) in AlertMuteDuration.allCases.enumerated() {
            add(duration.title, to: menu, action: #selector(muteForDuration)).tag = index
        }
    }

    private func addHeld(to menu: NSMenu) {
        guard !mute.held.isEmpty else { return }
        menu.addItem(.separator())
        addLabel(String(localized: "Susturulurken gelenler"), to: menu)
        for alert in mute.held.suffix(Self.maxListedAlerts).reversed() {
            let title = "\(alert.sourceLabel): \(alert.title)"
            let item = add(String(title.prefix(Self.maxTitleLength)), to: menu, action: #selector(openHeld))
            item.representedObject = alert.id
            item.isEnabled = alert.action != nil
        }
        add(String(localized: "Listeyi temizle"), to: menu, action: #selector(clearHeld))
    }

    private func addLabel(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    @discardableResult
    private func add(_ title: String, to menu: NSMenu, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func unmute() { mute.unmute() }
    @objc private func clearHeld() { mute.clearHeld() }

    @objc private func muteForDuration(_ sender: NSMenuItem) {
        guard AlertMuteDuration.allCases.indices.contains(sender.tag) else { return }
        mute.mute(for: AlertMuteDuration.allCases[sender.tag])
    }

    @objc private func openHeld(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        mute.held.first { $0.id == id }?.action?()
    }
}
