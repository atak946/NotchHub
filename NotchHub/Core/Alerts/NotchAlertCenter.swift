import Observation

/// Single queue of notch alerts shared by every display.
@MainActor
@Observable
final class NotchAlertCenter {
    static let maxQueuedAlerts = 5

    typealias Sleeper = @Sendable (Duration) async throws -> Void
    typealias Now = @Sendable () -> ContinuousClock.Instant

    private(set) var current: NotchAlert?
    private(set) var queue: [NotchAlert] = []
    /// Auto-dismiss progress of `current`; `nil` for alerts that stay until dismissed.
    private(set) var countdown: AlertCountdown?

    /// While hovered the current alert never auto-dismisses; the countdown pauses and resumes afterwards.
    var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            if isHovered {
                cancelDismiss()
                countdown = countdown?.paused(at: now())
            } else {
                countdown = countdown?.resumed(at: now())
                scheduleDismiss()
            }
        }
    }

    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private let sleep: Sleeper
    @ObservationIgnored private let now: Now

    init(
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
        now: @escaping Now = { ContinuousClock.now }
    ) {
        self.sleep = sleep
        self.now = now
    }

    func post(_ alert: NotchAlert) {
        if let key = alert.coalescingKey {
            if current?.coalescingKey == key {
                show(alert)
                return
            }
            queue = queue.filter { $0.coalescingKey != key }
        }

        if current == nil {
            show(alert)
        } else {
            queue = Array((queue + [alert]).suffix(Self.maxQueuedAlerts))
        }
    }

    func dismiss() {
        cancelDismiss()
        current = nil
        countdown = nil
        isHovered = false
        guard let next = queue.first else { return }
        queue = Array(queue.dropFirst())
        show(next)
    }

    func dismissAll() {
        queue = []
        dismiss()
    }

    func performAction() {
        let action = current?.action
        dismiss()
        action?()
    }

    func performSecondaryAction() {
        let action = current?.secondaryAction
        dismiss()
        action?()
    }

    /// "Göster": reveals the concealed text of the current alert and restarts its countdown
    /// (at least the default duration) so there is time to read it.
    func revealContent() {
        guard let alert = current, alert.isContentConcealed else { return }
        current = alert.revealingContent()
        guard let total = alert.autoDismissAfter else { return }
        countdown = AlertCountdown.started(total: max(total, NotchAlert.defaultDuration), at: now())
        if isHovered { countdown = countdown?.paused(at: now()) }
        scheduleDismiss()
    }

    private func show(_ alert: NotchAlert) {
        current = alert
        countdown = alert.autoDismissAfter.map { AlertCountdown.started(total: $0, at: now()) }
        // A replacement alert under the pointer starts paused, like the one it replaced.
        if isHovered { countdown = countdown?.paused(at: now()) }
        scheduleDismiss()
    }

    private func cancelDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }

    private func scheduleDismiss() {
        cancelDismiss()
        guard !isHovered, let alert = current, let countdown else { return }
        let duration = countdown.remaining(at: now())
        let alertID = alert.id
        let sleep = self.sleep
        dismissTask = Task { [weak self] in
            try? await sleep(duration)
            guard !Task.isCancelled, let self, self.current?.id == alertID else { return }
            self.dismiss()
        }
    }
}
