import AppKit
import SwiftUI

/// The menu bar item, built as a plain AppKit menu: SwiftUI's MenuBarExtra bridge made hovering
/// over the items stutter. Item states are refreshed in `menuNeedsUpdate` right before it opens.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private static let symbolName = "rectangle.topthird.inset.filled"
    private static let settingsSelector = Selector(("showSettingsWindow:"))

    private let settings: SettingsStore
    private let windowManager: NotchWindowManager
    private let updater: UpdaterService
    private let micMute: MicMuteController?
    private let supportActions: SupportActions

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var mirrorItem: NSMenuItem?
    private var pauseItem: NSMenuItem?
    private var micMuteItem: NSMenuItem?
    private var updatesItem: NSMenuItem?
    /// SwiftUI's `openSettings`, captured by a zero-size view hosted in the status item button.
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

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: Self.symbolName, accessibilityDescription: "NotchHub")
        buildMenu()
        item.menu = menu
        if let button = item.button {
            let capture = NSHostingView(rootView: SettingsActionCapture { [weak self] action in
                self?.openSettingsAction = action
            })
            capture.frame = .zero
            button.addSubview(capture)
        }
        statusItem = item
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        mirrorItem?.isEnabled = !settings.isPaused
        pauseItem?.state = settings.isPaused ? .on : .off
        micMuteItem?.isEnabled = micMute?.isAvailable ?? false
        updatesItem?.isHidden = !updater.isAvailable
    }

    // MARK: - Building

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        addItem(String(localized: "Paneli Aç/Kapat"), action: #selector(togglePanel), key: "n", modifiers: [.command, .option])
        mirrorItem = addItem(String(localized: "Ayna (kamerayı kontrol et)"), action: #selector(openCameraMirror))
        pauseItem = addItem(String(localized: "NotchHub'ı Duraklat"), action: #selector(togglePause))
        if micMute != nil {
            micMuteItem = addItem(
                String(localized: "Mikrofonu sustur/aç"), action: #selector(toggleMicMute), key: "m", modifiers: [.command, .option]
            )
        }
        menu.addItem(.separator())
        addItem(String(localized: "Ayarlar…"), action: #selector(openSettings), key: ",")
        addItem(String(localized: "Kurulum sihirbazı…"), action: #selector(openOnboarding))
        addItem(String(localized: "Sorun bildir…"), action: #selector(reportIssue))
        updatesItem = addItem(String(localized: "Güncellemeleri denetle…"), action: #selector(checkForUpdates))
        addItem(String(localized: "NotchHub'dan Çık"), action: #selector(quit), key: "q")
    }

    @discardableResult
    private func addItem(
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

    @objc private func openSettings() {
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
}

/// Hands SwiftUI's `openSettings` action to AppKit code.
private struct SettingsActionCapture: View {
    let onCapture: (OpenSettingsAction) -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear.onAppear { onCapture(openSettings) }
    }
}
