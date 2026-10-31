import Observation

/// The single level HUD shared by every display; a new reading replaces the current one and restarts its timer.
@MainActor
@Observable
final class NotchHUDCenter {
    static let displayDuration: Duration = .milliseconds(1600)

    typealias Sleeper = @Sendable (Duration) async throws -> Void

    private(set) var current: HUDReading?
    /// Bumped by every accepted `show`, so the view can react to a press that left the level unchanged.
    private(set) var showCount = 0
    /// While held (the bar is being dragged) the HUD stays up; releasing restarts the hide timer.
    private(set) var isHeld = false

    /// Set by the integrator: `false` drops readings (setting off, paused, or an alert is showing).
    @ObservationIgnored var canShow: @MainActor () -> Bool = { true }
    @ObservationIgnored private let sleep: Sleeper
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    func show(_ reading: HUDReading) {
        guard canShow() else { return }
        if current != reading { current = reading }
        showCount &+= 1
        if isHeld {
            hideTask?.cancel()
            hideTask = nil
        } else {
            scheduleHide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        isHeld = false
        if current != nil { current = nil }
    }

    /// Keeps the current reading on screen while `held`; ignored when nothing is shown.
    func setHeld(_ held: Bool) {
        guard held != isHeld else { return }
        guard !held || current != nil else { return }
        isHeld = held
        if held {
            hideTask?.cancel()
            hideTask = nil
        } else if current != nil {
            scheduleHide()
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        generation += 1
        let expected = generation
        let sleep = self.sleep
        hideTask = Task { [weak self] in
            do {
                try await sleep(Self.displayDuration)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.generation == expected else { return }
            self.hideTask = nil
            self.current = nil
        }
    }
}
