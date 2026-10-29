import AppKit
import Observation
import OSLog

/// Memory pressure, thermal state and low disk space, with coalesced alerts.
@MainActor
@Observable
final class SystemPressureMonitor {
    static let diskCheckInterval: TimeInterval = 10 * 60
    /// Re-raising the same severity within this window is suppressed (flapping signals).
    static let memoryCooldown: TimeInterval = 15 * 60
    static let thermalCooldown: TimeInterval = 15 * 60
    static let diskCooldown: TimeInterval = 6 * 60 * 60
    static let elevatedAlertDuration: Duration = .seconds(10)
    static let recoveredAlertDuration: Duration = .seconds(3)

    enum AlertKey {
        static let memory = "system.memory"
        static let thermal = "system.thermal"
        static let disk = "system.disk"
    }

    enum Keys {
        static let isEnabled = "SystemPressure.isEnabled"
        static let alertsEnabled = "SystemPressure.alertsEnabled"
        static let diskThresholdGigabytes = "SystemPressure.diskThresholdGigabytes"
    }

    private static let activityMonitorBundleID = "com.apple.ActivityMonitor"

    private(set) var memoryPressure: MemoryPressureLevel = .normal
    private(set) var thermalLevel: SystemThermalLevel = .nominal
    private(set) var freeDiskBytes: Int64?

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            applyRunningState()
        }
    }

    var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: Keys.alertsEnabled) }
    }

    var diskThresholdGigabytes: Int {
        didSet {
            defaults.set(diskThresholdGigabytes, forKey: Keys.diskThresholdGigabytes)
            if isMonitoring { checkDisk() }
        }
    }

    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let reader: any SystemPressureReading
    @ObservationIgnored private let clock: any SystemClock
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let diskPoller: SystemPoller
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "SystemPressure")
    @ObservationIgnored private var memoryGate = PressureAlertGate(cooldown: SystemPressureMonitor.memoryCooldown)
    @ObservationIgnored private var thermalGate = PressureAlertGate(cooldown: SystemPressureMonitor.thermalCooldown)
    @ObservationIgnored private var diskGate = PressureAlertGate(cooldown: SystemPressureMonitor.diskCooldown)
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private(set) var isMonitoring = false

    init(
        alerts: NotchAlertCenter,
        reader: any SystemPressureReading = SystemPressureReader(),
        clock: any SystemClock = SystemLiveClock(),
        defaults: UserDefaults = .standard
    ) {
        self.alerts = alerts
        self.reader = reader
        self.clock = clock
        self.defaults = defaults
        diskPoller = SystemPoller(clock: clock)
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        alertsEnabled = defaults.object(forKey: Keys.alertsEnabled) as? Bool ?? true
        let storedThreshold = defaults.object(forKey: Keys.diskThresholdGigabytes) as? Int
        diskThresholdGigabytes = storedThreshold.flatMap { DiskSpacePolicy.thresholdGigabyteOptions.contains($0) ? $0 : nil }
            ?? DiskSpacePolicy.defaultThresholdGigabytes
    }

    var isDiskLow: Bool {
        freeDiskBytes.map { DiskSpacePolicy.isLow(freeBytes: $0, thresholdGigabytes: diskThresholdGigabytes) } ?? false
    }

    /// Worst current severity across memory, thermal and disk (drives the tile tint).
    var worstSeverity: PressureSeverity {
        let disk = freeDiskBytes.map {
            DiskSpacePolicy.severity(freeBytes: $0, thresholdGigabytes: diskThresholdGigabytes)
        } ?? .none
        return [memoryPressure.severity, thermalLevel.severity, disk].max() ?? .none
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

    // MARK: - Inputs (internal for tests)

    func handleMemory(_ level: MemoryPressureLevel) {
        if level != memoryPressure {
            logger.info("Memory pressure: \(level.title, privacy: .public)")
            memoryPressure = level
        }
        let decision = memoryGate.evaluate(level.severity, at: clock.now)
        decision.map { postMemory($0, level: level) }
    }

    func handleThermal(_ level: SystemThermalLevel) {
        if level != thermalLevel {
            logger.info("Thermal state: \(level.title, privacy: .public)")
            thermalLevel = level
        }
        let decision = thermalGate.evaluate(level.severity, at: clock.now)
        decision.map { postThermal($0, level: level) }
    }

    func handleDisk(freeBytes: Int64) {
        if freeBytes != freeDiskBytes {
            freeDiskBytes = freeBytes
        }
        let severity = DiskSpacePolicy.severity(freeBytes: freeBytes, thresholdGigabytes: diskThresholdGigabytes)
        let decision = diskGate.evaluate(severity, at: clock.now)
        decision.map { postDisk($0, freeBytes: freeBytes) }
    }

    func checkDisk() {
        guard let free = reader.freeDiskBytes() else { return }
        handleDisk(freeBytes: free)
    }

    func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.activityMonitorBundleID) else {
            logger.error("Activity Monitor not found")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Alerts

    private func postMemory(_ decision: PressureAlertDecision, level: MemoryPressureLevel) {
        switch decision {
        case .raise(let severity):
            post(
                key: AlertKey.memory, systemImage: "memorychip.fill",
                title: severity == .critical ? String(localized: "Bellek baskısı kritik") : String(localized: "Bellek baskısı yüksek"),
                subtitle: String(localized: "İhtiyacın olmayan uygulamaları kapat"),
                severity: severity
            )
        case .recovered:
            postRecovered(key: AlertKey.memory, systemImage: "memorychip", title: String(localized: "Bellek baskısı normale döndü"))
        }
    }

    private func postThermal(_ decision: PressureAlertDecision, level: SystemThermalLevel) {
        switch decision {
        case .raise(let severity):
            post(
                key: AlertKey.thermal, systemImage: "thermometer.high",
                title: severity == .critical ? String(localized: "Mac aşırı ısındı") : String(localized: "Mac sıcak çalışıyor"),
                subtitle: String(localized: "Performans düşebilir"),
                severity: severity
            )
        case .recovered:
            postRecovered(key: AlertKey.thermal, systemImage: "thermometer.medium", title: String(localized: "Mac soğudu"))
        }
    }

    private func postDisk(_ decision: PressureAlertDecision, freeBytes: Int64) {
        switch decision {
        case .raise(let severity):
            post(
                key: AlertKey.disk, systemImage: "internaldrive.fill",
                title: severity == .critical ? String(localized: "Disk neredeyse dolu") : String(localized: "Disk alanı az"),
                subtitle: String(localized: "\(SystemFormat.bytes(freeBytes)) boş"),
                severity: severity
            )
        case .recovered:
            postRecovered(key: AlertKey.disk, systemImage: "internaldrive", title: String(localized: "Disk alanı düzeldi"))
        }
    }

    private func post(key: String, systemImage: String, title: String, subtitle: String, severity: PressureSeverity) {
        guard isEnabled, alertsEnabled else { return }
        let isCritical = severity == .critical
        alerts.post(NotchAlert(
            module: .status,
            systemImage: systemImage,
            title: title,
            subtitle: subtitle,
            style: isCritical ? .urgent : .reminder,
            coalescingKey: key,
            autoDismissAfter: isCritical ? nil : Self.elevatedAlertDuration,
            actionTitle: String(localized: "Etkinlik Monitörü"),
            action: { [weak self] in self?.openActivityMonitor() }
        ))
    }

    /// Replaces a lingering warning with the same key, then disappears on its own.
    private func postRecovered(key: String, systemImage: String, title: String) {
        guard isEnabled, alertsEnabled else { return }
        alerts.post(NotchAlert(
            module: .status,
            systemImage: systemImage,
            title: title,
            style: .success,
            coalescingKey: key,
            autoDismissAfter: Self.recoveredAlertDuration
        ))
    }

    // MARK: - Running state

    private func applyRunningState() {
        let shouldMonitor = isStarted && isEnabled
        if shouldMonitor, !isMonitoring {
            isMonitoring = true
            reader.startObserving(
                memory: { [weak self] level in self?.handleMemory(level) },
                thermal: { [weak self] level in self?.handleThermal(level) }
            )
            diskPoller.start(every: Self.diskCheckInterval) { [weak self] in self?.checkDisk() }
            handleMemory(reader.currentMemoryPressure())
            handleThermal(reader.currentThermalLevel())
            checkDisk()
        } else if !shouldMonitor, isMonitoring {
            isMonitoring = false
            reader.stopObserving()
            diskPoller.stop()
        }
    }
}
