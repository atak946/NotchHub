import AppKit
import Observation
import OSLog

/// Hides the menu bar icons left of a divider and lists them in a panel below the chevron, like the
/// hidden icons of the Windows taskbar. Needs Accessibility; without it nothing is hidden.
@MainActor
@Observable
final class MenuBarContainer {
    private static let enabledKey = "MenuBarContainer.isEnabled"
    private static let liveIconsKey = "MenuBarContainer.showsLiveIcons"
    private static let layoutDelay: Duration = .milliseconds(600)
    private static let refreshInterval: Duration = .seconds(1)
    private static let hiddenOpenTimeout: Duration = .milliseconds(1500)
    private static let menuGap: CGFloat = 4
    /// Longest time the icons stay on screen while a menu opens.
    private static let maxRevealTime: Duration = .milliseconds(400)
    private static let windowLayoutTime: Duration = .milliseconds(50)
    private static let lateWindowTimeout: Duration = .seconds(1)

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            apply()
        }
    }

    /// Shows the icons as the menu bar draws them instead of the apps' own icons.
    var showsLiveIcons: Bool {
        didSet {
            guard showsLiveIcons != oldValue else { return }
            defaults.set(showsLiveIcons, forKey: Self.liveIconsKey)
            if showsLiveIcons { requestCaptureAccess() } else { icons = [:] }
        }
    }

    /// macOS only reports a new grant after a relaunch.
    private(set) var isCaptureAllowed = MenuBarIconCapture.isAllowed
    private(set) var items: [MenuBarItem] = []
    /// Pictures by item id, only while `showsLiveIcons` is on and allowed.
    private(set) var icons: [String: MenuBarIconCapture.Icon] = [:]
    private(set) var isScanning = false
    /// The icons are in the menu bar so the user can move them across the divider.
    private(set) var isArranging = false

    /// Entries for the chevron's right-click menu; the app's own menu bar item may be hidden as well.
    @ObservationIgnored var makeMenu: (() -> NSMenu)?

    @ObservationIgnored private let permission: AccessibilityPermission
    @ObservationIgnored private let scanner = MenuBarItemScanner()
    @ObservationIgnored private let activator = MenuBarItemActivator()
    @ObservationIgnored private let capture = MenuBarIconCapture()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var strategies: MenuBarStrategyStore
    @ObservationIgnored private let menuCopy = MenuBarMenuCopy()
    @ObservationIgnored private var divider: MenuBarDivider?
    @ObservationIgnored private var panel: MenuBarContainerPanel?
    @ObservationIgnored private var anchor: Anchor?
    @ObservationIgnored private var installTask: Task<Void, Never>?
    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var hiddenAt = ContinuousClock.now
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "MenuBar")

    init(permission: AccessibilityPermission, defaults: UserDefaults = .standard) {
        self.permission = permission
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        showsLiveIcons = defaults.bool(forKey: Self.liveIconsKey)
        strategies = MenuBarStrategyStore(defaults: defaults)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        permission.refresh()
        trackPermission()
        apply()
    }

    func stop() {
        isStarted = false
        apply()
    }

    /// Screenshot mode only: fills the box without reading the menu bar.
    func setDemo(items: [MenuBarItem], icons: [String: MenuBarIconCapture.Icon]) {
        self.items = items
        self.icons = icons
    }

    // MARK: - Panel actions

    var needsCaptureAccess: Bool { showsLiveIcons && !isCaptureAllowed }

    func requestCaptureAccess() {
        panel?.dismiss()
        MenuBarIconCapture.requestAccess()
        isCaptureAllowed = MenuBarIconCapture.isAllowed
    }

    func startArranging() {
        panel?.dismiss()
        openTask?.cancel()
        isArranging = true
        divider?.reveal()
    }

    /// Opens what the icon opens below the chevron, if possible without showing the icons.
    func open(_ item: MenuBarItem, button: CGMouseButton = .left) {
        panel?.dismiss()
        openTask?.cancel()
        guard let anchor = anchor ?? currentAnchor() else { return }
        openTask = Task { [weak self] in
            await self?.open(item, button: button, anchor: anchor)
        }
    }

    private func open(_ item: MenuBarItem, button: CGMouseButton, anchor: Anchor) async {
        // Apps that keep a menu on their icon show it on a right click, whatever a left click does.
        if button == .right, await showMenuCopy(of: item, anchor: anchor) { return }
        guard !Task.isCancelled else { return }
        switch strategies[item.bundleID, button] {
        case .copyMenu:
            if await showMenuCopy(of: item, anchor: anchor) { return }
            guard !Task.isCancelled else { return }
            strategies[item.bundleID, button] = .reveal
            await openRevealed(item, button: button, anchor: anchor)
        case .reveal:
            await openRevealed(item, button: button, anchor: anchor)
        case nil:
            await openHidden(item, button: button, anchor: anchor)
        }
    }

    /// Clicks the icon where it is and brings what opens below the chevron.
    private func openHidden(_ item: MenuBarItem, button: CGMouseButton, anchor: Anchor) async {
        let before = activator.openWindows(of: item)
        guard await activator.click(item, button: button) else { return }
        let outcome = await activator.settle(
            item, notIn: before, anchor: anchor.target, screen: anchor.bounds, timeout: Self.hiddenOpenTimeout
        )
        guard !Task.isCancelled else { return }
        switch outcome {
        case .movedWindow, .visible:
            return
        case .menu:
            await activator.cancelMenu(of: item, notIn: before)
            guard !Task.isCancelled else { return }
            if await showMenuCopy(of: item, anchor: anchor) {
                strategies[item.bundleID, button] = .copyMenu
                return
            }
            strategies[item.bundleID, button] = .reveal
            await openRevealed(item, button: button, anchor: anchor)
        case .stuck:
            strategies[item.bundleID, button] = .reveal
            await activator.cancelMenu(of: item, notIn: before)
            guard !Task.isCancelled else { return }
            await openRevealed(item, button: button, anchor: anchor)
        case .nothingOpened:
            // Not repeated: the click may have run an action or closed a window that was open. A menu
            // that stays shut while its icon is hidden gets the icon on screen next time.
            if await activator.hasMenu(item), await MenuBarMenuReader.read(item) == nil {
                strategies[item.bundleID, button] = .reveal
                await openRevealed(item, button: button, anchor: anchor)
            }
        }
    }

    private func showMenuCopy(of item: MenuBarItem, anchor: Anchor) async -> Bool {
        guard let nodes = await MenuBarMenuReader.read(item), !Task.isCancelled else { return false }
        menuCopy.show(nodes, at: CGPoint(x: anchor.frame.minX, y: anchor.frame.minY - Self.menuGap))
        return true
    }

    /// Last resort: the icon is on screen for a moment and hidden again as soon as something opened.
    private func openRevealed(_ item: MenuBarItem, button: CGMouseButton, anchor: Anchor) async {
        let before = activator.openWindows(of: item)
        divider?.reveal()
        let isOnScreen = await activator.waitUntilOnScreen(item, screens: Self.screenFrames())
        guard !Task.isCancelled else { return }
        guard isOnScreen, await activator.click(item, button: button) else {
            logger.error("A hidden icon could not be clicked on screen")
            hideIfIdle()
            return
        }
        _ = await activator.waitForWindow(of: item, notIn: before, timeout: Self.maxRevealTime)
        // Hidden any earlier, some apps lay their window out for an icon that is gone.
        try? await Task.sleep(for: Self.windowLayoutTime)
        guard !Task.isCancelled else { return }
        hideIfIdle()
        _ = await activator.settle(
            item, notIn: before, anchor: anchor.target, screen: anchor.bounds, timeout: Self.lateWindowTimeout
        )
    }

    // MARK: - Installing

    private var shouldRun: Bool { isStarted && isEnabled && permission.isTrusted }

    private func apply() {
        if shouldRun, divider == nil {
            install()
        } else if !shouldRun, divider != nil || installTask != nil {
            uninstall()
        }
    }

    private func install() {
        guard installTask == nil else { return }
        installTask = Task { [weak self, scanner] in
            let items = await scanner.scan(MenuBarItemScanner.runningApps())
            guard !Task.isCancelled, let self, self.shouldRun else { return }
            let systemFrames = items
                .filter { $0.bundleID == MenuBarItemScanner.controlCenterBundleID && $0.identifier != nil }
                .map(\.frame)
            let position = MenuBarLayout.preferredPosition(systemItems: systemFrames, screens: Self.screenFrames())
            self.makeDivider(position: position)
            try? await Task.sleep(for: Self.layoutDelay)
            guard !Task.isCancelled, self.shouldRun else { return }
            if self.divider?.hide() == false {
                self.logger.error("Divider is not left of the chevron; starting from the default place")
                self.divider?.remove()
                MenuBarDivider.resetPositions(in: self.defaults)
                self.makeDivider(position: position)
                try? await Task.sleep(for: Self.layoutDelay)
                guard !Task.isCancelled, self.shouldRun else { return }
                self.divider?.hide()
            }
            self.installTask = nil
            self.hiddenAt = .now
            await self.refreshItems()
        }
    }

    private func makeDivider(position: CGFloat?) {
        let divider = MenuBarDivider(position: position, defaults: defaults)
        divider.onClick = { [weak self] in self?.handleClick($0) }
        self.divider = divider
    }

    private func uninstall() {
        installTask?.cancel()
        installTask = nil
        openTask?.cancel()
        panel?.dismiss()
        divider?.remove()
        divider = nil
        items = []
        icons = [:]
        isArranging = false
    }

    private func trackPermission() {
        withObservationTracking {
            _ = permission.isTrusted
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isStarted else { return }
                self.trackPermission()
                self.apply()
            }
        }
    }

    // MARK: - Chevron

    private func handleClick(_ event: NSEvent) {
        if event.type == .rightMouseUp {
            showMenu()
        } else if isArranging {
            isArranging = false
            hideIfIdle()
        } else if panel?.isVisible == true {
            panel?.dismiss()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard permission.refresh() else { return apply() }
        openTask?.cancel()
        // Icons still shown from an earlier press go back first.
        hideIfIdle()
        guard let anchor = currentAnchor() else { return }
        self.anchor = anchor
        let panel = MenuBarContainerPanel(content: MenuBarContainerView(container: self))
        panel.onClose = { [weak self] in self?.panel = nil }
        // Captured icons are black or white like the menu bar they come from.
        panel.appearance = divider?.menuBarAppearance
        self.panel = panel
        panel.show(below: anchor.frame, on: anchor.screen)
        Task { await refreshWhilePanelIsOpen() }
    }

    private func showMenu() {
        panel?.dismiss()
        guard let anchor = currentAnchor() else { return }
        let menu = makeMenu?() ?? NSMenu()
        menu.popUp(positioning: nil, at: CGPoint(x: anchor.frame.minX, y: anchor.frame.minY), in: nil)
    }

    /// The menu bar repeats on every screen but the item has one window, so a click on another screen's
    /// bar hangs below the pointer instead.
    private func currentAnchor() -> Anchor? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? .main else { return nil }
        if let frame = divider?.chevronFrame, frame.insetBy(dx: -2, dy: -8).contains(mouse) {
            return Anchor(frame: frame, screen: screen)
        }
        let width = NSStatusItem.squareLength > 0 ? NSStatusItem.squareLength : NSStatusBar.system.thickness
        let barHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        let frame = CGRect(x: mouse.x - width / 2, y: screen.frame.maxY - barHeight, width: width, height: barHeight)
        return Anchor(frame: frame, screen: screen)
    }

    // MARK: - State

    private func hideIfIdle() {
        guard let divider, !isArranging, !divider.isHiding else { return }
        guard divider.hide() else {
            logger.error("Divider was moved right of the chevron; icons stay visible")
            return
        }
        hiddenAt = .now
    }

    /// Icons that show a value as text ("● 3") keep it current in the panel.
    private func refreshWhilePanelIsOpen() async {
        guard let opened = panel else { return }
        while panel === opened {
            await refreshItems()
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    private func refreshItems() async {
        isScanning = true
        defer { isScanning = false }
        // Right after hiding, apps still report where their icons used to be.
        let settling = Self.layoutDelay - hiddenAt.duration(to: .now)
        if settling > .zero { try? await Task.sleep(for: settling) }
        let scanned = await scanner.scan(MenuBarItemScanner.runningApps())
        guard let divider, divider.isHiding, let cocoaFrame = divider.dividerFrame else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let hidden = MenuBarLayout.hiddenItems(
            in: scanned.filter { $0.pid != ownPID },
            divider: Self.topLeftBased(cocoaFrame)
        )
        // Pictures first, so the panel does not flash the apps' own icons.
        isCaptureAllowed = MenuBarIconCapture.isAllowed
        if showsLiveIcons, panel != nil { icons = await capture.icons(for: hidden) }
        items = hidden
        guard let panel, let anchor else { return }
        // The grid's size follows on the next layout pass.
        try? await Task.sleep(for: .milliseconds(30))
        panel.reposition(below: anchor.frame, on: anchor.screen)
    }

    // MARK: - Coordinates

    /// Where things hang from: the chevron in Cocoa coordinates and the screen it was clicked on.
    private struct Anchor {
        let frame: CGRect
        let screen: NSScreen

        /// Top-left based, as Accessibility and the window server count.
        @MainActor var target: CGRect { MenuBarContainer.topLeftBased(frame) }
        @MainActor var bounds: CGRect { MenuBarContainer.topLeftBased(screen.frame) }
    }

    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    private static func topLeftBased(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func screenFrames() -> [CGRect] {
        NSScreen.screens.map { topLeftBased($0.frame) }
    }
}
