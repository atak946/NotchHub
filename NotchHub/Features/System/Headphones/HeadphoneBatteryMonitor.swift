import Foundation
import Observation
import OSLog

/// Shows a notch alert with battery levels when a Bluetooth headset connects (or becomes the output).
@MainActor
@Observable
final class HeadphoneBatteryMonitor {
    /// Freshly connected devices need a moment before they report battery levels.
    static let settleDelay: TimeInterval = 2
    static let readTimeout: Duration = .seconds(3)
    /// "Device added" and "default output changed" arrive together on connect; one read covers both.
    static let duplicateWindow: TimeInterval = 15
    static let alertDuration: Duration = .seconds(4)
    static let alertKey = "headphones.battery"

    enum Keys {
        static let isEnabled = "Headphones.batteryAlertsEnabled"
    }

    private(set) var lastReport: HeadphoneBatteryReport?
    /// Connected Bluetooth outputs, for the status tile.
    private(set) var snapshot: BluetoothAudioSnapshot = .empty

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            applyRunningState()
        }
    }

    @ObservationIgnored var canPostAlert: @MainActor () -> Bool = { true }

    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let watcher: any BluetoothAudioWatching
    @ObservationIgnored private let reader: any HeadphoneBatteryReading
    @ObservationIgnored private let clock: any SystemClock
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Headphones")
    @ObservationIgnored private var lastTriggered: [String: Date] = [:]
    /// The in-flight read; exposed so tests can await it.
    @ObservationIgnored private(set) var pendingRead: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private(set) var isMonitoring = false

    init(
        alerts: NotchAlertCenter,
        watcher: any BluetoothAudioWatching = CoreAudioBluetoothWatcher(),
        reader: any HeadphoneBatteryReading = SystemProfilerBatteryReader(),
        clock: any SystemClock = SystemLiveClock(),
        defaults: UserDefaults = .standard
    ) {
        self.alerts = alerts
        self.watcher = watcher
        self.reader = reader
        self.clock = clock
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
    }

    var connectedOutput: BluetoothAudioOutput? {
        snapshot.defaultBluetoothOutput ?? snapshot.outputs.first
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

    /// Diffs the CoreAudio state; a connect (or switch to a headset) triggers one battery read.
    func handleChange() {
        let previous = snapshot
        let current = watcher.snapshot()
        guard current != previous else { return }
        snapshot = current
        guard let device = HeadphoneConnectPolicy.connectedDevice(previous: previous, current: current) else { return }
        let now = clock.now
        guard !HeadphoneConnectPolicy.isDuplicate(
            name: device.name, lastTriggered: lastTriggered, now: now, window: Self.duplicateWindow
        ) else { return }
        lastTriggered[device.name] = now
        scheduleRead(for: device.name)
    }

    // MARK: - Private

    private func scheduleRead(for name: String) {
        pendingRead?.cancel()
        let clock = clock
        let reader = reader
        pendingRead = Task { [weak self] in
            do {
                try await clock.sleep(for: .seconds(Self.settleDelay))
            } catch {
                return
            }
            let levels = await reader.readLevels(deviceName: name, timeout: Self.readTimeout)
            guard !Task.isCancelled else { return }
            self?.finishRead(name: name, levels: levels)
        }
    }

    private func finishRead(name: String, levels: HeadphoneBatteryLevels?) {
        pendingRead = nil
        guard isMonitoring, let levels, !levels.isEmpty else { return }
        lastReport = HeadphoneBatteryReport(deviceName: name, levels: levels, readAt: clock.now)
        // Disconnected while reading: show nothing.
        guard snapshot.contains(name: name), canPostAlert() else { return }
        alerts.post(NotchAlert(
            module: .status,
            systemImage: HeadphoneBatteryFormatter.deviceGlyph(for: name),
            title: name,
            subtitle: HeadphoneBatteryFormatter.subtitle(levels),
            style: .info,
            coalescingKey: Self.alertKey,
            autoDismissAfter: Self.alertDuration
        ))
        logger.info("Posted headset battery alert")
    }

    private func applyRunningState() {
        let shouldMonitor = isStarted && isEnabled
        if shouldMonitor, !isMonitoring {
            isMonitoring = true
            // Baseline: devices already connected at launch are not "connect events".
            snapshot = watcher.snapshot()
            watcher.startObserving { [weak self] in self?.handleChange() }
        } else if !shouldMonitor, isMonitoring {
            isMonitoring = false
            watcher.stopObserving()
            pendingRead?.cancel()
            pendingRead = nil
            snapshot = .empty
        }
    }
}
