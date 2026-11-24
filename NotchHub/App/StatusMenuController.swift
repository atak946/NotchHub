import AppKit
import SwiftUI

/// Fallback menu bar item. The app's menu lives in the notch header; the item only appears while no notch
/// can be opened (paused, or no display shows one), so the app always stays reachable.
@MainActor
final class StatusMenuController {
    private static let symbolName = "rectangle.topthird.inset.filled"

    private let appMenu: AppMenuController
    private var statusItem: NSStatusItem?

    init(appMenu: AppMenuController) {
        self.appMenu = appMenu
    }

    func setVisible(_ isVisible: Bool) {
        if isVisible {
            install()
        } else {
            remove()
        }
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: Self.symbolName, accessibilityDescription: "NotchHub")
        item.menu = appMenu.makeStatusMenu()
        if let button = item.button {
            let capture = NSHostingView(rootView: appMenu.settingsActionCapture)
            capture.frame = .zero
            button.addSubview(capture)
        }
        statusItem = item
    }

    private func remove() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }
}
