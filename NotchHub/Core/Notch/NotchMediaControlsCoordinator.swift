import AppKit
import Observation

/// Drives the collapsed media controls for one notch: reveals them while the pointer is over their
/// rect, keeps the click catcher there, routes clicks to `MediaService` and mirrors the hovered button
/// into the view model.
@MainActor
final class NotchMediaControlsCoordinator {
    /// How long the controls linger after the pointer leaves, so a small overshoot does not flicker.
    static let hideDelay: Duration = .milliseconds(450)

    private let model: NotchViewModel
    private let alerts: NotchAlertCenter
    private let catcher = MediaControlsCatcherPanel()
    /// Whether the owning notch panel is on screen; the catcher only shows alongside it.
    private var isHostVisible = false
    private var isTornDown = false
    private var hideTask: Task<Void, Never>?

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
        let isInZone = isInteractive && revealRect?.contains(point) == true
        let hovered = isInZone
            ? model.geometry.mediaControlAction(at: point, wingWidth: model.wingWidth, afterMicMute: afterMicMute)
            : nil
        if model.hoveredMediaControl != hovered {
            model.hoveredMediaControl = hovered
        }
        isInZone ? reveal() : scheduleHide()
    }

    /// Whether the mic button sits before the controls.
    var afterMicMute: Bool { model.showsMicMuteButton }

    func tearDown() {
        isTornDown = true
        hideTask?.cancel()
        onOpenPanel = nil
        catcher.onClick = nil
        catcher.orderOut(nil)
        catcher.close()
    }

    // MARK: - Private

    private var revealRect: CGRect? {
        model.geometry.mediaControlsRevealRect(wingWidth: model.wingWidth, afterMicMute: afterMicMute)
    }

    private func reveal() {
        hideTask?.cancel()
        hideTask = nil
        if !model.isMediaControlsRevealed { model.isMediaControlsRevealed = true }
    }

    private func scheduleHide() {
        guard model.isMediaControlsRevealed, hideTask == nil else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hideDelay)
            guard !Task.isCancelled, let self else { return }
            self.hideTask = nil
            self.model.isMediaControlsRevealed = false
        }
    }

    private func hideNow() {
        hideTask?.cancel()
        hideTask = nil
        if model.isMediaControlsRevealed { model.isMediaControlsRevealed = false }
    }

    private func handleClick(at point: CGPoint) {
        reveal()
        let route = model.geometry.clickRoute(
            at: point, wingWidth: model.wingWidth, mediaControlsActive: isInteractive, afterMicMute: afterMicMute
        )
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
        guard isHostVisible, isInteractive, let rect = model.geometry.mediaControlsRect(
            wingWidth: model.wingWidth, afterMicMute: afterMicMute
        ) else {
            catcher.orderOut(nil)
            if model.hoveredMediaControl != nil { model.hoveredMediaControl = nil }
            hideNow()
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
