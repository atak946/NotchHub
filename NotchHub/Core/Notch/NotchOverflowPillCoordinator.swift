import AppKit
import Observation

/// Keeps a click catcher over the collapsed "+N" status pill so a click opens the Status tab
/// instead of falling through to the menu bar underneath.
@MainActor
final class NotchOverflowPillCoordinator {
    /// Called on a click on the pill; the controller selects Status and expands.
    var onOpenStatus: (() -> Void)?

    private let model: NotchViewModel
    private let alerts: NotchAlertCenter
    private let panelFrame: () -> CGRect
    private let catcher = MediaControlsCatcherPanel()
    private var isHostVisible = false
    private var isTornDown = false

    init(model: NotchViewModel, alerts: NotchAlertCenter, panelFrame: @escaping () -> CGRect) {
        self.model = model
        self.alerts = alerts
        self.panelFrame = panelFrame
        catcher.onClick = { [weak self] in
            self?.onOpenStatus?()
        }
        trackState()
    }

    func setHostVisible(_ isVisible: Bool) {
        isHostVisible = isVisible
        updateCatcher()
    }

    func tearDown() {
        isTornDown = true
        catcher.onClick = nil
        onOpenStatus = nil
        catcher.orderOut(nil)
        catcher.close()
    }

    private var catcherRect: CGRect? {
        guard isHostVisible, !model.isExpanded, alerts.current == nil,
              model.settings.isEnabled(.status),
              let pill = model.overflowPillFrame, !pill.isEmpty
        else { return nil }
        let slack = NotchGeometry.overflowPillHitSlack
        return NotchGeometry.screenRect(ofViewRect: pill, inPanelFrame: panelFrame())
            .insetBy(dx: -slack, dy: -slack)
    }

    private func trackState() {
        withObservationTracking {
            _ = model.overflowPillFrame
            _ = model.geometry
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
        guard let rect = catcherRect else {
            catcher.orderOut(nil)
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
