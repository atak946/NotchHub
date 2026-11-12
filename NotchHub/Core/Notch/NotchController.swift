import AppKit
import Observation
import SwiftUI

/// Owns one notch panel on one display and drives hover open/close, drops and alerts.
@MainActor
final class NotchController {
    private static let escapeKeyCode: UInt16 = 53
    private static let closeDelay: Duration = .milliseconds(120)

    let displayID: CGDirectDisplayID
    private let settings: SettingsStore
    private let alerts: NotchAlertCenter
    private let model: NotchViewModel
    private let panel: NotchPanel
    private let dropCatcher: DropCatcherPanel
    private let mediaControls: NotchMediaControlsCoordinator
    private let micMute: NotchMicMuteCoordinator
    private let overflowPill: NotchOverflowPillCoordinator
    private var monitors: [Any] = []
    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    /// Opened by keyboard, reminder or click: stays open until the pointer visits and leaves, or a click outside.
    private var isPinnedOpen = false
    private var isTornDown = false

    var isExpanded: Bool { model.isExpanded }
    var isVisible: Bool { panel.isVisible }

    init(
        screen: NSScreen,
        displayID: CGDirectDisplayID,
        settings: SettingsStore,
        services: ModuleServices,
        alerts: NotchAlertCenter
    ) {
        let geometry = screen.notchGeometry
        self.displayID = displayID
        self.settings = settings
        self.alerts = alerts
        self.model = NotchViewModel(geometry: geometry, settings: settings, services: services)
        self.panel = NotchPanel(contentRect: geometry.panelRect)
        self.dropCatcher = DropCatcherPanel(contentRect: geometry.collapsedRect)
        self.mediaControls = NotchMediaControlsCoordinator(model: model, alerts: alerts)
        self.micMute = NotchMicMuteCoordinator(model: model, alerts: alerts)
        let panel = self.panel
        self.overflowPill = NotchOverflowPillCoordinator(model: model, alerts: alerts, panelFrame: { panel.frame })

        let hostingView = NSHostingView(rootView: NotchRootView(model: model, alerts: alerts, displayID: displayID))
        hostingView.frame = CGRect(origin: .zero, size: geometry.panelRect.size)
        panel.contentView = hostingView
        panel.setFrame(geometry.panelRect, display: true)

        model.onOpenModule = { [weak self] module in
            self?.open(module, makeKey: false)
        }
        dropCatcher.onDragEnter = { [weak self] in
            self?.openShelfForDrop()
        }
        dropCatcher.onClick = { [weak self] in
            self?.selectStatusIfOnOverflowPill()
            self?.expand(pinned: true)
        }
        mediaControls.onOpenPanel = { [weak self] in
            self?.expand(pinned: true)
        }
        overflowPill.onOpenStatus = { [weak self] in
            self?.model.select(.status)
            self?.expand(pinned: true)
        }
        installMonitors()
        trackAlerts()
        trackCameraMirror()
        trackHUD()
    }

    func update(screen: NSScreen) {
        let geometry = screen.notchGeometry
        guard geometry != model.geometry else { return }
        model.geometry = geometry
        panel.setFrame(geometry.panelRect, display: true)
        dropCatcher.setFrame(geometry.collapsedRect, display: false)
    }

    func show() {
        guard !panel.isVisible else { return }
        dropCatcher.orderFrontRegardless()
        panel.orderFrontRegardless()
        mediaControls.setHostVisible(true)
        micMute.setHostVisible(true)
        overflowPill.setHostVisible(true)
    }

    func hide() {
        // A hidden notch must not keep the camera running.
        if isCameraMirrorShown { cameraMirror.close() }
        collapse()
        panel.orderOut(nil)
        dropCatcher.orderOut(nil)
        mediaControls.setHostVisible(false)
        micMute.setHostVisible(false)
        overflowPill.setHostVisible(false)
    }

    func toggle() {
        if model.isExpanded {
            collapse()
        } else {
            show()
            expand(pinned: true, makeKey: true)
        }
    }

    /// Expands on a specific module (used by alerts and reminders).
    func open(_ module: NotchModule, makeKey: Bool) {
        guard panel.isVisible else { return }
        model.select(module)
        if model.isExpanded {
            model.attentionCount += 1
        } else {
            expand(pinned: true, makeKey: makeKey)
        }
    }

    func tearDown() {
        isTornDown = true
        if isCameraMirrorShown { cameraMirror.close() }
        cancelPendingTasks()
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        model.onOpenModule = nil
        dropCatcher.onDragEnter = nil
        dropCatcher.onClick = nil
        panel.orderOut(nil)
        panel.close()
        dropCatcher.orderOut(nil)
        dropCatcher.close()
        mediaControls.tearDown()
        micMute.tearDown()
        overflowPill.tearDown()
    }

    // MARK: - State

    private func expand(pinned: Bool = false, makeKey: Bool = false) {
        // The mirror outranks the panel; opening the panel ends the camera check.
        if isCameraMirrorShown { cameraMirror.close() }
        cancelPendingTasks()
        isPinnedOpen = pinned
        guard !model.isExpanded else { return }
        model.isExpanded = true
        updateMouseInteractivity()
        if makeKey {
            panel.makeKey()
        }
    }

    private func collapse() {
        cancelPendingTasks()
        isPinnedOpen = false
        guard model.isExpanded else { return }
        model.isExpanded = false
        updateMouseInteractivity()
        if panel.isKeyWindow {
            // resignKey() alone leaves the nonactivating panel key and swallows keystrokes;
            // re-ordering hands key status back to the frontmost app's window.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    /// Clicks pass through to the menu bar unless the panel or an alert banner is showing.
    private func updateMouseInteractivity(at point: CGPoint = NSEvent.mouseLocation) {
        // The window spans the whole expanded area plus shadow margins; only the visible
        // panel or alert may take clicks, everything around it must reach the apps below.
        // A bar drag keeps the clicks until the button is released, even outside the strip.
        let shouldAccept = (interactiveRect?.contains(point) ?? false) || hud.center.isHeld
        // Once the window stops taking mouse events SwiftUI never sees the hover end,
        // which would leave the alert countdown paused forever.
        if !shouldAccept, alerts.isHovered {
            alerts.isHovered = false
        }
        if panel.ignoresMouseEvents == shouldAccept {
            panel.ignoresMouseEvents = !shouldAccept
        }
    }

    private var interactiveRect: CGRect? {
        NotchPresentation.resolve(
            isCameraMirrorShown: isCameraMirrorShown,
            isExpanded: model.isExpanded,
            hasAlert: alerts.current != nil,
            hasHUD: hud.isAdjustableOnScreen // Only an adjustable HUD takes clicks, on its bar strip.
        ).interactiveRect(in: model.geometry)
    }

    private func cancelPendingTasks() {
        openTask?.cancel()
        openTask = nil
        closeTask?.cancel()
        closeTask = nil
    }

    private func trackAlerts() {
        withObservationTracking {
            _ = alerts.current?.id
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isTornDown else { return }
                self.handleAlertChange()
                self.trackAlerts()
            }
        }
    }

    private func handleAlertChange() {
        updateMouseInteractivity()
        guard model.isExpanded, let module = alerts.current?.module else { return }
        // Panel already open: jump to the alert's module and shake instead of showing a banner.
        model.select(module)
        model.attentionCount += 1
    }

    // MARK: - HUD

    private var hud: SystemHUD { model.services.hud }

    /// The HUD is what this notch shows and it can be scrolled or dragged.
    private var isHUDAdjustable: Bool {
        hud.isAdjustableOnScreen && !model.isExpanded && alerts.current == nil && !isCameraMirrorShown
    }

    private func trackHUD() {
        withObservationTracking {
            _ = hud.isAdjustableOnScreen
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isTornDown else { return }
                self.updateMouseInteractivity()
                self.trackHUD()
            }
        }
    }

    /// Scrolling anywhere over the visible HUD changes its level; the pending hover-open is dropped.
    private func handleScroll(_ scroll: HUDScroll, at point: CGPoint) {
        guard panel.isVisible, !scroll.isMomentum, scroll.deltaY != 0, isHUDAdjustable,
              model.geometry.hudRect.contains(point)
        else { return }
        openTask?.cancel()
        openTask = nil
        hud.adjust(byScroll: scroll.deltaY, isPrecise: scroll.isPrecise, isInverted: scroll.isInverted)
    }

    // MARK: - Events

    private func installMonitors() {
        let mouseMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            let isDragging = event.type == .leftMouseDragged
            MainActor.assumeIsolated { self?.handleMouseMove(to: NSEvent.mouseLocation, isDragging: isDragging) }
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            let isDragging = event.type == .leftMouseDragged
            MainActor.assumeIsolated { self?.handleMouseMove(to: NSEvent.mouseLocation, isDragging: isDragging) }
            return event
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.handleOutsideClick(at: NSEvent.mouseLocation) }
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            let scroll = HUDScroll(event)
            MainActor.assumeIsolated { self?.handleScroll(scroll, at: NSEvent.mouseLocation) }
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            let scroll = HUDScroll(event)
            MainActor.assumeIsolated { self?.handleScroll(scroll, at: NSEvent.mouseLocation) }
            return event
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let keyCode = event.keyCode
            let isHandled = MainActor.assumeIsolated { self?.handleKeyDown(keyCode) ?? false }
            return isHandled ? nil : event
        }) {
            monitors.append(monitor)
        }
    }

    private func handleMouseMove(to point: CGPoint, isDragging: Bool) {
        guard panel.isVisible else { return }
        updateMouseInteractivity(at: point)
        let geometry = model.geometry

        if model.isExpanded {
            if geometry.shouldClose(at: point) {
                if !isPinnedOpen, !isHoldingKeyboardFocus { scheduleClose() }
            } else {
                isPinnedOpen = false
                closeTask?.cancel()
                closeTask = nil
            }
            return
        }

        // The alert banner handles its own hover and clicks; the media controls never start the open timer.
        mediaControls.updateHover(at: point)
        micMute.updateHover(at: point)
        // Dragging or reaching for the HUD bar never opens the panel over it.
        if hud.center.isHeld || (isHUDAdjustable && geometry.hudBarRect.contains(point)) {
            openTask?.cancel()
            openTask = nil
            return
        }
        let isOpenTrigger = geometry.shouldOpen(
            at: point,
            wingWidth: model.wingWidth,
            excludingMediaControls: mediaControls.isInteractive
        ) && !micMute.blocksOpen(at: point)
        guard alerts.current == nil, !isCameraMirrorShown, isOpenTrigger else {
            openTask?.cancel()
            openTask = nil
            return
        }

        if isDragging {
            openShelfForDrop()
        } else {
            scheduleOpen()
        }
    }

    /// Dragging something onto the notch opens the shelf immediately as a drop target.
    private func openShelfForDrop() {
        guard panel.isVisible, settings.isEnabled(.shelf), !model.isExpanded else { return }
        model.select(.shelf)
        expand()
        panel.orderFrontRegardless()
    }

    /// A focused note editor keeps the panel open when the pointer leaves; Esc and outside clicks still close it.
    private var isHoldingKeyboardFocus: Bool {
        panel.isKeyWindow && model.services.notes.isEditorFocused
    }

    private func handleOutsideClick(at point: CGPoint) {
        if isCameraMirrorShown, !model.geometry.cameraMirrorRect.contains(point) {
            cameraMirror.close()
            return
        }
        guard model.isExpanded, model.geometry.shouldClose(at: point) else { return }
        collapse()
    }

    private func handleKeyDown(_ keyCode: UInt16) -> Bool {
        guard keyCode == Self.escapeKeyCode else { return false }
        if isCameraMirrorShown {
            cameraMirror.close()
            return true
        }
        if model.isExpanded {
            collapse()
            return true
        }
        if alerts.current != nil {
            alerts.dismiss()
            return true
        }
        return false
    }

    private func scheduleOpen() {
        guard openTask == nil else { return }
        let delay = Duration.milliseconds(Int(settings.hoverDelay * 1000))
        openTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.openTask = nil
            self?.selectStatusIfOnOverflowPill()
            self?.expand()
        }
    }

    /// The "+N" pill stands for status glyphs that did not fit, so opening from it shows the Status tab.
    private func selectStatusIfOnOverflowPill() {
        guard settings.isEnabled(.status), NotchGeometry.isOnOverflowPill(
            NSEvent.mouseLocation, pillFrame: model.overflowPillFrame, panelFrame: panel.frame
        ) else { return }
        model.select(.status)
    }

    private func scheduleClose() {
        guard closeTask == nil else { return }
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.closeDelay)
            guard !Task.isCancelled else { return }
            self?.closeTask = nil
            self?.collapse()
        }
    }

    // MARK: - Camera mirror

    private var cameraMirror: CameraMirrorService { model.services.cameraMirror.service }

    private var isCameraMirrorShown: Bool { cameraMirror.isShown(on: displayID) }

    private func trackCameraMirror() {
        withObservationTracking {
            _ = isCameraMirrorShown
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isTornDown else { return }
                self.handleCameraMirrorChange()
                self.trackCameraMirror()
            }
        }
    }

    /// The mirror collapses the panel and takes key focus so Esc closes it; closing hands focus back.
    private func handleCameraMirrorChange() {
        if isCameraMirrorShown {
            collapse()
            updateMouseInteractivity()
            panel.makeKey()
        } else {
            updateMouseInteractivity()
            if !model.isExpanded, panel.isKeyWindow {
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
        }
    }
}

/// The parts of a scroll-wheel event the HUD needs, copied out so they can cross into the main actor.
private struct HUDScroll: Sendable {
    let deltaY: Double
    let isPrecise: Bool
    let isInverted: Bool
    /// Trackpad inertia after the fingers lift; ignored so the level never runs on by itself.
    let isMomentum: Bool

    init(_ event: NSEvent) {
        deltaY = Double(event.scrollingDeltaY)
        isPrecise = event.hasPreciseScrollingDeltas
        isInverted = event.isDirectionInvertedFromDevice
        isMomentum = !event.momentumPhase.isEmpty
    }
}
