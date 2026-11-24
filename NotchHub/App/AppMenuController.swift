import AppKit
import SwiftUI

/// The app's menu (settings, pause, support, quit), shared by the notch header button and the fallback
/// menu bar item. Plain AppKit: SwiftUI's menu bridge made hovering over the items stutter.
@MainActor
final class AppMenuController: NSObject, NSMenuDelegate {
    private static let settingsSelector = Selector(("showSettingsWindow:"))

    private let settings: SettingsStore
    private let windowManager: NotchWindowManager
    private let updater: UpdaterService
    private let micMute: MicMuteController?
    private let supportActions: SupportActions

    /// SwiftUI's `openSettings`, captured by a `SettingsActionCapture` in the notch panel or the menu bar item.
    private var openSettingsAction: OpenSettingsAction?

    init(
        settings: SettingsStore,
        windowManager: NotchWindowManager,
        updater: UpdaterService,
        micMute: MicMuteController?,
        supportActions: SupportActions
    ) {
        self.settings = settings
        self.windowManager = windowManager
        self.updater = updater
        self.micMute = micMute
        self.supportActions = supportActions
        super.init()
    }

    /// Menu for the notch header; it opens from the panel, so it has no item to toggle the panel.
    func makeNotchMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        populate(menu, includesPanelToggle: false)
        return menu
    }

    /// Menu for the menu bar item; refreshed right before it opens.
    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        return menu
    }

    var settingsActionCapture: SettingsActionCapture {
        SettingsActionCapture { [weak self] action in
            self?.openSettingsAction = action
        }
    }

    @objc func openSettings() {
        NSApp.activate()
        if let openSettingsAction {
            openSettingsAction()
        } else {
            NSApp.sendAction(Self.settingsSelector, to: nil, from: nil)
        }
        // An LSUIElement app is not brought forward by activate(); raise the window explicitly.
        DispatchQueue.main.async {
            let window = NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
            window?.makeKeyAndOrderFront(nil)
            window?.orderFrontRegardless()
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu, includesPanelToggle: true)
    }

    // MARK: - Building

    private func populate(_ menu: NSMenu, includesPanelToggle: Bool) {
        menu.removeAllItems()
        if includesPanelToggle {
            addItem(
                to: menu, String(localized: "Paneli Aç/Kapat"),
                action: #selector(togglePanel), key: "n", modifiers: [.command, .option]
            )
        }
        addItem(to: menu, String(localized: "Ayna (kamerayı kontrol et)"), action: #selector(openCameraMirror))
            .isEnabled = !settings.isPaused
        addItem(to: menu, String(localized: "NotchHub'ı Duraklat"), action: #selector(togglePause))
            .state = settings.isPaused ? .on : .off
        if let micMute {
            addItem(
                to: menu, String(localized: "Mikrofonu sustur/aç"),
                action: #selector(toggleMicMute), key: "m", modifiers: [.command, .option]
            ).isEnabled = micMute.isAvailable
        }
        menu.addItem(.separator())
        addItem(to: menu, String(localized: "Ayarlar…"), action: #selector(openSettings), key: ",")
        addItem(to: menu, String(localized: "Kurulum sihirbazı…"), action: #selector(openOnboarding))
        addItem(to: menu, String(localized: "Sorun bildir…"), action: #selector(reportIssue))
        if updater.isAvailable {
            addItem(to: menu, String(localized: "Güncellemeleri denetle…"), action: #selector(checkForUpdates))
        }
        addItem(to: menu, String(localized: "NotchHub'dan Çık"), action: #selector(quit), key: "q")
    }

    @discardableResult
    private func addItem(
        to menu: NSMenu,
        _ title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: - Actions

    @objc private func togglePanel() { windowManager.togglePanel() }
    @objc private func openCameraMirror() { windowManager.openCameraMirror() }
    @objc private func togglePause() { settings.isPaused.toggle() }
    @objc private func toggleMicMute() { micMute?.toggle() }
    @objc private func openOnboarding() { supportActions.openOnboarding() }
    @objc private func reportIssue() { supportActions.reportIssue() }
    @objc private func checkForUpdates() { updater.checkForUpdates() }
    @objc private func quit() { NSApp.terminate(nil) }
}

/// Hands SwiftUI's `openSettings` action to AppKit code.
struct SettingsActionCapture: View {
    let onCapture: (OpenSettingsAction) -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear.onAppear { onCapture(openSettings) }
    }
}
