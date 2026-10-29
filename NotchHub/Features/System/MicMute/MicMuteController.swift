import Foundation
import Observation
import OSLog

/// System-wide microphone mute on the default input device (works for every meeting app).
/// Remembers what it changed so quitting, crashing or switching devices never leaves a mic silenced.
@MainActor
@Observable
final class MicMuteController {
    static let feedbackDuration: Duration = .milliseconds(1500)
    static let feedbackAlertKey = "micMute.feedback"

    enum Keys {
        static let isHotKeyEnabled = "MicMute.isHotKeyEnabled"
    }

    private(set) var isMuted = false
    /// A default input device exists and can be muted (property or volume).
    private(set) var isAvailable = false
    private(set) var deviceName: String?

    /// ⌥⌘M toggles the mute from anywhere.
    var isHotKeyEnabled: Bool {
        didSet { defaults.set(isHotKeyEnabled, forKey: Keys.isHotKeyEnabled) }
    }

    /// Gate for the short "Mikrofon kapalı / açık" feedback alert.
    @ObservationIgnored var canPostAlert: @MainActor () -> Bool = { true }

    @ObservationIgnored private let hardware: any MicInputHardware
    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let store: MicMuteRecordStore
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "MicMute")
    @ObservationIgnored private(set) var record: MicMuteRecord?
    @ObservationIgnored private var currentUID: String?
    @ObservationIgnored private(set) var isStarted = false

    init(
        alerts: NotchAlertCenter,
        hardware: any MicInputHardware = CoreAudioMicInput(),
        defaults: UserDefaults = .standard
    ) {
        self.alerts = alerts
        self.hardware = hardware
        self.defaults = defaults
        store = MicMuteRecordStore(defaults: defaults)
        isHotKeyEnabled = defaults.object(forKey: Keys.isHotKeyEnabled) as? Bool ?? true
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        recoverFromPreviousSession()
        hardware.startObserving { [weak self] in self?.sync() }
        sync()
    }

    /// Stops observing and restores whatever NotchHub muted (called on quit).
    func stop() {
        guard isStarted else { return }
        isStarted = false
        hardware.stopObserving()
        restoreOriginalState()
        currentUID = nil
        update(from: hardware.defaultInputState())
    }

    // MARK: - Commands

    func toggle() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        guard isStarted else { return }
        guard let state = hardware.defaultInputState() else {
            logger.error("No default input device to \(muted ? "mute" : "unmute", privacy: .public)")
            return
        }
        let succeeded = muted ? mute(state) : unmute(state)
        sync()
        if succeeded {
            postFeedback()
        } else {
            logger.error("Microphone \(muted ? "mute" : "unmute", privacy: .public) failed")
        }
    }

    /// Re-reads the default input: follows device switches and mute changes made by other apps.
    func sync() {
        var state = hardware.defaultInputState()
        if state?.uid != currentUID {
            handleDeviceChange(to: state)
            state = hardware.defaultInputState()
        }
        let reconciled = MicMutePolicy.reconciledRecord(record, state: state)
        if reconciled != record {
            logger.info("Microphone unmuted elsewhere; dropping mute record")
            saveRecord(reconciled)
        }
        update(from: state)
    }

    // MARK: - Private

    private func mute(_ state: MicInputState) -> Bool {
        guard !MicMutePolicy.isMuted(state) else { return true }
        guard let plan = MicMutePolicy.mutePlan(for: state) else { return false }
        // Persist first: a crash right after the HAL write is still recoverable on the next launch.
        saveRecord(plan.record)
        guard perform(plan.actions, uid: state.uid) else {
            saveRecord(nil)
            return false
        }
        return true
    }

    private func unmute(_ state: MicInputState) -> Bool {
        let succeeded = perform(MicMutePolicy.unmutePlan(for: state, record: record), uid: state.uid)
        if succeeded { saveRecord(nil) }
        return succeeded
    }

    /// Keeps the user's intent across a device switch: releases the old device and silences the new one.
    private func handleDeviceChange(to state: MicInputState?) {
        let isFirstRead = currentUID == nil
        currentUID = state?.uid
        guard !isFirstRead, let record, record.deviceUID != state?.uid else { return }
        restore(record)
        saveRecord(nil)
        if let state {
            logger.info("Default input changed while muted; muting the new device")
            if !mute(state) { logger.error("Muting the new default input failed") }
        }
    }

    private func recoverFromPreviousSession() {
        guard let stored = store.load() else { return }
        logger.info("Restoring microphone muted by a previous session")
        restore(stored)
        saveRecord(nil)
    }

    private func restoreOriginalState() {
        guard let record else { return }
        restore(record)
        saveRecord(nil)
    }

    private func restore(_ record: MicMuteRecord) {
        guard let state = hardware.state(forUID: record.deviceUID) else {
            logger.info("Muted input device is gone; nothing to restore")
            return
        }
        if !perform(MicMutePolicy.restorePlan(for: state, record: record), uid: state.uid) {
            logger.error("Restoring microphone state failed")
        }
    }

    private func perform(_ actions: [MicMuteAction], uid: String) -> Bool {
        var succeeded = true
        for action in actions where !hardware.apply(action, toUID: uid) {
            succeeded = false
        }
        return succeeded
    }

    private func saveRecord(_ newRecord: MicMuteRecord?) {
        record = newRecord
        store.save(newRecord)
    }

    private func update(from state: MicInputState?) {
        let available = MicMutePolicy.isAvailable(state)
        let muted = MicMutePolicy.isMuted(state)
        if isAvailable != available { isAvailable = available }
        if isMuted != muted { isMuted = muted }
        if deviceName != state?.name { deviceName = state?.name }
    }

    private func postFeedback() {
        guard canPostAlert() else { return }
        alerts.post(NotchAlert(
            module: nil,
            systemImage: isMuted ? "mic.slash.fill" : "mic.fill",
            title: isMuted ? String(localized: "Mikrofon kapalı") : String(localized: "Mikrofon açık"),
            subtitle: deviceName,
            style: .info,
            coalescingKey: Self.feedbackAlertKey,
            autoDismissAfter: Self.feedbackDuration
        ))
    }
}
