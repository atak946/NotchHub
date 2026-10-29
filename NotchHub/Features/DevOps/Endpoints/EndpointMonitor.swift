import Foundation
import Observation
import OSLog

/// Latest observation of one endpoint.
struct EndpointStatus: Equatable, Sendable {
    var state: EndpointHealthState = .unknown
    var latency: TimeInterval?
    var statusCode: Int?
    var lastError: String?
    var lastChecked: Date?
    var certificateExpiry: Date?
}

/// Polls user-managed HTTP(S) endpoints, tracks up/down/degraded and warns about expiring certificates.
@MainActor
@Observable
final class EndpointMonitor {
    private enum Keys {
        static let isEnabled = "Endpoints.isEnabled"
        static let alertsEnabled = "Endpoints.alertsEnabled"
        static let certificateWarnings = "Endpoints.certificateWarnings"
    }

    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let store: EndpointStore
    @ObservationIgnored private let prober: any EndpointProber
    @ObservationIgnored private let vpn: any VPNDetector
    @ObservationIgnored private let clock: any DevOpsClock
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var machines: [UUID: EndpointHealthMachine] = [:]
    @ObservationIgnored private var certificatePolicy: CertificateExpiryWarningPolicy
    @ObservationIgnored private var pollTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private let logger = Logger(subsystem: DevOpsConstants.logSubsystem, category: "Endpoints")

    private(set) var endpoints: [MonitoredEndpoint]
    private(set) var statuses: [UUID: EndpointStatus] = [:]

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            isEnabled ? start() : stop()
        }
    }

    var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: Keys.alertsEnabled) }
    }

    init(
        alerts: NotchAlertCenter,
        defaults: UserDefaults = .standard,
        prober: any EndpointProber = URLSessionEndpointProber(),
        vpn: any VPNDetector = InterfaceVPNDetector(),
        clock: any DevOpsClock = SystemDevOpsClock(),
        calendar: Calendar = .current
    ) {
        self.alerts = alerts
        self.defaults = defaults
        self.prober = prober
        self.vpn = vpn
        self.clock = clock
        self.calendar = calendar
        store = EndpointStore(defaults: defaults)
        endpoints = store.load()
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        alertsEnabled = defaults.object(forKey: Keys.alertsEnabled) as? Bool ?? true
        certificatePolicy = CertificateExpiryWarningPolicy(lastWarnings: Self.loadWarnings(from: defaults))
    }

    // MARK: - Derived state

    func status(for id: UUID) -> EndpointStatus {
        statuses[id] ?? EndpointStatus()
    }

    var downEndpoints: [MonitoredEndpoint] {
        endpoints.filter { statuses[$0.id]?.state == .down }
    }

    var hasCompactIndicator: Bool {
        isEnabled && !downEndpoints.isEmpty
    }

    /// Worst state across all endpoints, for the tile tint.
    var overallState: EndpointHealthState {
        let states = endpoints.map { status(for: $0.id).state }
        if states.contains(.down) { return .down }
        if states.contains(.degraded) { return .degraded }
        if states.contains(.up) { return .up }
        if !states.isEmpty, states.allSatisfy({ $0 == .pausedVPNOff }) { return .pausedVPNOff }
        return .unknown
    }

    // MARK: - List management

    @discardableResult
    func add(_ endpoint: MonitoredEndpoint) -> [EndpointValidationError] {
        let errors = EndpointValidator.validate(endpoint)
        guard errors.isEmpty else { return errors }
        endpoints = endpoints + [Self.normalized(endpoint)]
        persist()
        restartPolling(for: endpoint.id)
        return []
    }

    @discardableResult
    func update(_ endpoint: MonitoredEndpoint) -> [EndpointValidationError] {
        let errors = EndpointValidator.validate(endpoint)
        guard errors.isEmpty else { return errors }
        guard endpoints.contains(where: { $0.id == endpoint.id }) else { return add(endpoint) }
        endpoints = endpoints.map { $0.id == endpoint.id ? Self.normalized(endpoint) : $0 }
        machines[endpoint.id] = nil
        statuses[endpoint.id] = nil
        persist()
        restartPolling(for: endpoint.id)
        return []
    }

    func remove(id: UUID) {
        endpoints = endpoints.filter { $0.id != id }
        pollTasks.removeValue(forKey: id)?.cancel()
        machines[id] = nil
        statuses[id] = nil
        certificatePolicy.forget(endpointID: id)
        saveWarnings()
        persist()
    }

    // MARK: - Lifecycle

    func start() {
        guard isEnabled, !isStarted else { return }
        isStarted = true
        logger.info("Endpoint monitor started with \(self.endpoints.count) endpoints")
        endpoints.forEach { restartPolling(for: $0.id) }
    }

    func stop() {
        isStarted = false
        pollTasks.values.forEach { $0.cancel() }
        pollTasks = [:]
    }

    /// Checks every endpoint once, outside the regular schedule.
    func checkAllNow() {
        for endpoint in endpoints {
            Task { await check(endpoint.id) }
        }
    }

    // MARK: - Checking (internal for tests)

    func check(_ id: UUID) async {
        guard let endpoint = endpoints.first(where: { $0.id == id }) else { return }
        if endpoint.requiresVPN, !vpn.isVPNActive() {
            apply(outcome: .vpnUnavailable, result: nil, to: endpoint)
            return
        }
        let result = await prober.probe(endpoint)
        guard endpoints.contains(where: { $0.id == id }) else { return }
        let outcome = EndpointCheckOutcome.classify(result, expected: endpoint.expectedStatus)
        apply(outcome: outcome, result: result, to: endpoint)
        if let expiry = result.certificateExpiry {
            evaluateCertificate(expiry, for: endpoint)
        }
    }

    private func apply(outcome: EndpointCheckOutcome, result: EndpointProbeResult?, to endpoint: MonitoredEndpoint) {
        var machine = machines[endpoint.id] ?? EndpointHealthMachine()
        let transition = machine.record(outcome)
        machines[endpoint.id] = machine

        var status = statuses[endpoint.id] ?? EndpointStatus()
        status.state = machine.state
        status.lastChecked = clock.now
        if let result {
            status.latency = result.errorDescription == nil ? result.latency : nil
            status.statusCode = result.statusCode
            status.lastError = result.errorDescription ?? Self.unexpectedStatusText(result, endpoint: endpoint)
            status.certificateExpiry = result.certificateExpiry ?? status.certificateExpiry
        }
        statuses[endpoint.id] = status

        if let transition {
            logger.info("Endpoint \(endpoint.displayName, privacy: .public): \(String(describing: transition), privacy: .public)")
            postAlert(for: transition, endpoint: endpoint)
        }
    }

    private func evaluateCertificate(_ expiry: Date, for endpoint: MonitoredEndpoint) {
        let now = clock.now
        guard certificatePolicy.shouldWarn(endpointID: endpoint.id, expiry: expiry, now: now, calendar: calendar) else {
            return
        }
        saveWarnings()
        guard alertsEnabled else { return }
        let days = CertificateExpiryWarningPolicy.daysRemaining(until: expiry, now: now, calendar: calendar)
        let subtitle: String
        if expiry <= now {
            subtitle = "Sertifikanın süresi doldu"
        } else if days <= 0 {
            subtitle = "Sertifika bugün bitiyor"
        } else {
            subtitle = "Sertifika bitişine \(days) gün var"
        }
        alerts.post(NotchAlert(
            module: .status,
            systemImage: "lock.trianglebadge.exclamationmark",
            title: endpoint.displayName,
            subtitle: subtitle,
            style: .reminder,
            coalescingKey: "endpoint.cert.\(endpoint.id.uuidString)",
            autoDismissAfter: NotchAlert.importantDuration
        ))
    }

    private func postAlert(for transition: EndpointTransition, endpoint: MonitoredEndpoint) {
        guard alertsEnabled else { return }
        let key = "endpoint.state.\(endpoint.id.uuidString)"
        switch transition {
        case .wentDown(let reason):
            alerts.post(NotchAlert(
                module: .status,
                systemImage: "bolt.horizontal.circle.fill",
                title: "\(endpoint.displayName) kapalı",
                subtitle: reason,
                style: .urgent,
                coalescingKey: key,
                autoDismissAfter: NotchAlert.importantDuration
            ))
        case .recovered:
            alerts.post(NotchAlert(
                module: .status,
                systemImage: "checkmark.circle.fill",
                title: "\(endpoint.displayName) tekrar ayakta",
                style: .success,
                coalescingKey: key
            ))
        }
    }

    // MARK: - Polling

    private func restartPolling(for id: UUID) {
        pollTasks.removeValue(forKey: id)?.cancel()
        guard isStarted, let endpoint = endpoints.first(where: { $0.id == id }) else { return }
        let interval = Duration.seconds(endpoint.intervalSeconds)
        let clock = clock
        pollTasks[id] = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.check(id)
                do {
                    try await clock.sleep(for: interval)
                } catch {
                    return
                }
            }
        }
    }

    // MARK: - Persistence

    private func persist() {
        do {
            try store.save(endpoints)
        } catch {
            logger.error("Failed to save endpoints: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveWarnings() {
        let encoded = Dictionary(uniqueKeysWithValues: certificatePolicy.lastWarnings.map {
            ($0.key.uuidString, $0.value.timeIntervalSinceReferenceDate)
        })
        defaults.set(encoded, forKey: Keys.certificateWarnings)
    }

    private static func loadWarnings(from defaults: UserDefaults) -> [UUID: Date] {
        guard let raw = defaults.dictionary(forKey: Keys.certificateWarnings) as? [String: Double] else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            UUID(uuidString: key).map { ($0, Date(timeIntervalSinceReferenceDate: value)) }
        })
    }

    private static func normalized(_ endpoint: MonitoredEndpoint) -> MonitoredEndpoint {
        var copy = endpoint
        copy.name = endpoint.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.url = endpoint.url.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    private static func unexpectedStatusText(_ result: EndpointProbeResult, endpoint: MonitoredEndpoint) -> String? {
        guard let code = result.statusCode, !endpoint.expectedStatus.contains(code) else { return nil }
        return "HTTP \(code)"
    }
}
