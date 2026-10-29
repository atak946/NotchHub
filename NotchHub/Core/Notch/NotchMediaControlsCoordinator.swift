import AppKit
import Observation

/// Drives the collapsed media controls for one notch: keeps the click catcher over the controls
/// rect, routes clicks to `MediaService` and mirrors the hovered button into the view model.
@MainActor
final class NotchMediaControlsCoordinator {
    private let model: NotchViewModel
    private let alerts: NotchAlertCenter
    private let catcher = MediaControlsCatcherPanel()
    /// Whether the owning notch panel is on screen; the catcher only shows alongside it.
    private var isHostVisible = false
    private var isTornDown = false

    /// Called for a click that lands on the notch itself rather than a control.
    var onOpenPanel: (() -> Void)?

    init(model: NotchViewModel, alerts: NotchAlertCenter) {
        self.model = model
        self.alerts = alerts
        catcher.onClick = { [weak self] in
            self?.handleClick(at: NSEvent.mouseLocation)
        }
        trackState()
    }

    /// The controls take clicks and block hover-to-open.
    var isInteractive: Bool {
        CompactMediaControls.isInteractive(
            isAvailable: model.showsMediaControls,
            isAlertShowing: alerts.current != nil,
            isExpanded: model.isExpanded
        )
    }

    func setHostVisible(_ isVisible: Bool) {
        isHostVisible = isVisible
        updateCatcher()
    }

    func updateHover(at point: CGPoint) {
        let hovered = isInteractive ? model.geometry.mediaControlAction(at: point, wingWidth: model.wingWidth) : nil
        if model.hoveredMediaControl != hovered {
            model.hoveredMediaControl = hovered
        }
    }

    func tearDown() {
        isTornDown = true
        onOpenPanel = nil
        catcher.onClick = nil
        catcher.orderOut(nil)
        catcher.close()
    }

    // MARK: - Private

    private func handleClick(at point: CGPoint) {
        let route = model.geometry.clickRoute(at: point, wingWidth: model.wingWidth, mediaControlsActive: isInteractive)
        switch route {
        case .mediaControl(let action):
            perform(action)
        case .openPanel:
            onOpenPanel?()
        case .passThrough:
            break
        }
    }

    private func perform(_ action: MediaControlAction) {
        let media = model.services.media
        switch action {
        case .previous: media.previous()
        case .playPause: media.playPause()
        case .next: media.next()
        }
        model.registerPress(action)
    }

    private func trackState() {
        withObservationTracking {
            _ = model.geometry
            _ = model.wingWidth
            _ = model.showsMediaControls
            _ = model.isExpanded
            _ = alerts.current?.id
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isTornDown else { return }
                self.updateCatcher()
                self.trackState()
            }
        }
    }

    private func updateCatcher() {
        guard !isTornDown else { return }
        guard isHostVisible, isInteractive, let rect = model.geometry.mediaControlsRect(wingWidth: model.wingWidth) else {
            catcher.orderOut(nil)
            if model.hoveredMediaControl != nil { model.hoveredMediaControl = nil }
            return
        }
        if catcher.frame != rect {
            catcher.setFrame(rect, display: true)
        }
        if !catcher.isVisible {
            catcher.orderFrontRegardless()
        }
    }
}
