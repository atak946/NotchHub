import Observation

/// Single queue of notch alerts shared by every display.
@MainActor
@Observable
final class NotchAlertCenter {
    static let maxQueuedAlerts = 5

    typealias Sleeper = @Sendable (Duration) async throws -> Void
    typealias Now = @Sendable () -> ContinuousClock.Instant

    private(set) var current: NotchAlert?
    private(set) var queue: [NotchAlert] = [] {
        didSet { speedUpForBusyQueue() }
    }
    /// Auto-dismiss progress of `current`; `nil` for alerts that stay until dismissed.
    private(set) var countdown: AlertCountdown?

    /// While hovered the countdown pauses and resumes afterwards; a hover longer than
    /// `AlertTiming.maxHoverHold` (e.g. a pointer parked under the notch) dismisses the alert anyway.
    var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            if isHovered {
                cancelDismiss()
                countdown = countdown?.paused(at: now())
                scheduleHoverHoldLimit()
            } else {
                cancelHoverHoldLimit()
                countdown = countdown?.resumed(at: now())
                scheduleDismiss()
            }
        }
    }

    /// User preference multiplier for alert durations (Settings › Notifications).
    @ObservationIgnored var durationScale: @MainActor () -> Double = { 1 }

    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var hoverHoldTask: Task<Void, Never>?
    /// When the current chain of same-key alerts started.
    @ObservationIgnored private var chainStartedAt: ContinuousClock.Instant?
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
                show(alert, continuingChain: true)
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
        cancelHoverHoldLimit()
        current = nil
        countdown = nil
        chainStartedAt = nil
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
        guard let base = alert.autoDismissAfter else { return }
        let total = effectiveDuration(max(base, NotchAlert.defaultDuration), for: alert)
        countdown = AlertCountdown.started(total: total, at: now())
        if isHovered { countdown = countdown?.paused(at: now()) }
        scheduleDismiss()
    }

    private func show(_ alert: NotchAlert, continuingChain: Bool = false) {
        let start = now()
        if !continuingChain || chainStartedAt == nil { chainStartedAt = start }
        current = alert
        countdown = alert.autoDismissAfter.map { base in
            var total = effectiveDuration(base, for: alert)
            if continuingChain, let chainStartedAt {
                total = AlertTiming.coalescedDuration(total: total, elapsedInChain: chainStartedAt.duration(to: start))
            }
            return AlertCountdown.started(total: total, at: start)
        }
        // A replacement alert under the pointer starts paused, like the one it replaced.
        if isHovered { countdown = countdown?.paused(at: start) }
        scheduleDismiss()
    }

    private func effectiveDuration(_ base: Duration, for alert: NotchAlert) -> Duration {
        AlertTiming.duration(
            base: base,
            scale: durationScale(),
            queuedCount: queue.count,
            pulses: alert.style.pulses
        )
    }

    /// A growing queue shortens the alert on screen so the burst drains quickly.
    private func speedUpForBusyQueue() {
        guard let alert = current, let countdown, let base = alert.autoDismissAfter else { return }
        let target = effectiveDuration(base, for: alert)
        let at = now()
        guard countdown.remaining(at: at) > target else { return }
        let shortened = AlertCountdown(total: countdown.total, remaining: target, resumedAt: countdown.isRunning ? at : nil)
        self.countdown = shortened
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

    private func cancelHoverHoldLimit() {
        hoverHoldTask?.cancel()
        hoverHoldTask = nil
    }

    /// Only auto-dismissing alerts are limited; persistent ones wait for the user as before.
    private func scheduleHoverHoldLimit() {
        cancelHoverHoldLimit()
        guard let alert = current, countdown != nil else { return }
        let alertID = alert.id
        let sleep = self.sleep
        hoverHoldTask = Task { [weak self] in
            do { try await sleep(AlertTiming.maxHoverHold) } catch { return }
            guard !Task.isCancelled, let self, self.isHovered, self.current?.id == alertID else { return }
            self.dismiss()
        }
    }
}
