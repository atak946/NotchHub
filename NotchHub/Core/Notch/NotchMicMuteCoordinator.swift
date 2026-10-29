import AppKit
import Observation

/// Drives the collapsed meeting mic button for one notch: keeps a click catcher over the button rect
/// (the rest of the wing stays click-through) and toggles `MicMuteController` on click.
@MainActor
final class NotchMicMuteCoordinator {
    private let model: NotchViewModel
    private let alerts: NotchAlertCenter
    /// The media catcher is a plain transparent click target; reused for this one-button rect.
    private let catcher = MediaControlsCatcherPanel()
    private var isHostVisible = false
    private var isTornDown = false

    init(model: NotchViewModel, alerts: NotchAlertCenter) {
        self.model = model
        self.alerts = alerts
        catcher.onClick = { [weak self] in
            self?.handleClick(at: NSEvent.mouseLocation)
        }
        trackState()
    }

    var isInteractive: Bool {
        CompactMicMute.isInteractive(
            isAvailable: model.showsMicMuteButton,
            isAlertShowing: alerts.current != nil,
            isExpanded: model.isExpanded
        )
    }

    /// The button never starts the hover-to-open timer while it takes clicks.
    func blocksOpen(at point: CGPoint) -> Bool {
        isInteractive && model.geometry.isOnMicMuteButton(point, wingWidth: model.wingWidth)
    }

    func setHostVisible(_ isVisible: Bool) {
        isHostVisible = isVisible
        updateCatcher()
    }

    func updateHover(at point: CGPoint) {
        let isHovered = blocksOpen(at: point)
        if model.isMicMuteHovered != isHovered {
            model.isMicMuteHovered = isHovered
        }
    }

    func tearDown() {
        isTornDown = true
        catcher.onClick = nil
        catcher.orderOut(nil)
        catcher.close()
    }

    // MARK: - Private

    private func handleClick(at point: CGPoint) {
        guard blocksOpen(at: point) else { return }
        model.services.system.micMute.toggle()
    }

    private func trackState() {
        withObservationTracking {
            _ = model.geometry
            _ = model.wingWidth
            _ = model.showsMicMuteButton
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
        guard isHostVisible, isInteractive, let rect = model.geometry.micMuteButtonRect(wingWidth: model.wingWidth) else {
            catcher.orderOut(nil)
            if model.isMicMuteHovered { model.isMicMuteHovered = false }
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
