import Observation
import OSLog

/// Detects meetings (mic + meeting app / calendar meeting), shows elapsed time and pauses music.
@MainActor
@Observable
final class MeetingModeController {
    /// Enter/exit must hold this long so a brief mic blip doesn't toggle meeting mode.
    static let debounceInterval: TimeInterval = 3
    /// Re-check pace so calendar meetings that start while the mic is already on are noticed.
    static let pollInterval: TimeInterval = 30

    enum Keys {
        static let isEnabled = "MeetingMode.isEnabled"
        static let autoPauseMusic = "MeetingMode.autoPauseMusic"
    }

    private(set) var session: MeetingSession?

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            applyRunningState()
        }
    }

    var autoPauseMusic: Bool {
        didSet { defaults.set(autoPauseMusic, forKey: Keys.autoPauseMusic) }
    }

    @ObservationIgnored private let inputs: any MeetingModeInputs
    @ObservationIgnored private let media: any MeetingMediaControlling
    @ObservationIgnored private let clock: any SystemClock
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let settleAction: SystemDelayedAction
    @ObservationIgnored private let poller: SystemPoller
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "MeetingMode")
    @ObservationIgnored private var debouncer = SystemDebouncer<Bool>(holdInterval: MeetingModeController.debounceInterval)
    @ObservationIgnored private var candidateSource: String?
    @ObservationIgnored private(set) var didPauseMedia = false
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private(set) var isMonitoring = false

    init(
        inputs: any MeetingModeInputs,
        media: any MeetingMediaControlling,
        clock: any SystemClock = SystemLiveClock(),
        defaults: UserDefaults = .standard
    ) {
        self.inputs = inputs
        self.media = media
        self.clock = clock
        self.defaults = defaults
        settleAction = SystemDelayedAction(clock: clock)
        poller = SystemPoller(clock: clock)
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        autoPauseMusic = defaults.object(forKey: Keys.autoPauseMusic) as? Bool ?? true
    }

    var isInMeeting: Bool { session != nil }

    var hasCompactIndicator: Bool { isEnabled && isInMeeting }

    func elapsed(at date: Date) -> TimeInterval {
        session.map { date.timeIntervalSince($0.start) } ?? 0
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        applyRunningState()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        applyRunningState()
    }

    /// Reads the inputs once and feeds the debouncer.
    func evaluate() {
        let now = clock.now
        let source = MeetingDetector.source(
            micInUse: inputs.isMicrophoneInUse,
            meetingApps: inputs.runningMeetingApps,
            calendarMeeting: MeetingDetector.calendarMeeting(in: inputs.calendarEvents, at: now)
        )
        if let source { candidateSource = source }
        let pendingSinceBefore = debouncer.pendingSince
        if let committed = debouncer.observe(source != nil, at: now) {
            apply(committed, since: pendingSinceBefore ?? now)
        }
        scheduleSettleIfNeeded()
    }

    /// Commits a pending enter/exit once it has been held for `debounceInterval`.
    func settle() {
        let since = debouncer.pendingSince
        if let committed = debouncer.settle(at: clock.now) {
            apply(committed, since: since ?? clock.now)
        }
        scheduleSettleIfNeeded()
    }

    // MARK: - Private

    private func apply(_ inMeeting: Bool, since: Date) {
        if inMeeting, session == nil {
            enter(at: since)
        } else if !inMeeting, session != nil {
            exit()
        }
    }

    private func enter(at start: Date) {
        session = MeetingSession(start: start, source: candidateSource ?? "Toplantı")
        logger.info("Meeting mode on")
        if MeetingMediaPolicy.shouldPauseOnEnter(autoPause: autoPauseMusic, isPlaying: media.isMediaPlaying) {
            media.playPause()
            didPauseMedia = true
        }
    }

    private func exit() {
        session = nil
        candidateSource = nil
        logger.info("Meeting mode off")
        if MeetingMediaPolicy.shouldResumeOnExit(didPause: didPauseMedia, isPlaying: media.isMediaPlaying) {
            media.playPause()
        }
        didPauseMedia = false
    }

    private func scheduleSettleIfNeeded() {
        guard let settleDate = debouncer.settleDate else {
            settleAction.cancel()
            return
        }
        settleAction.schedule(after: settleDate.timeIntervalSince(clock.now)) { [weak self] in
            self?.settle()
        }
    }

    private func applyRunningState() {
        let shouldMonitor = isStarted && isEnabled
        if shouldMonitor, !isMonitoring {
            isMonitoring = true
            trackInputs()
            poller.start(every: Self.pollInterval) { [weak self] in self?.evaluate() }
            evaluate()
        } else if !shouldMonitor, isMonitoring {
            isMonitoring = false
            poller.stop()
            settleAction.cancel()
            debouncer.reset()
            if session != nil { exit() }
        }
    }

    private func trackInputs() {
        withObservationTracking {
            _ = inputs.isMicrophoneInUse
            _ = inputs.runningMeetingApps
            _ = inputs.calendarEvents
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isMonitoring else { return }
                self.evaluate()
                self.trackInputs()
            }
        }
    }
}
