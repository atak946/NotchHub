import Foundation
import Observation
import OSLog

/// Receives alerts from scripts (`notchhub://` URLs and the local socket), validates, rate limits
/// and posts them to the notch.
@MainActor
@Observable
final class ExternalAlertService {
    static let socketFileName = "notchhub.sock"
    static let appSupportFolder = "NotchHub"
    static let defaultMinimumCommandSeconds = 30
    static let minimumSecondsEnvironmentKey = "NOTCHHUB_MIN_SECONDS"
    static let zshHookPlaceholderPath = "/path/to/NotchHub/tools/Integrations/notchhub.zsh"
    static let openActionTitle = String(localized: "Aç")
    static let revealActionTitle = String(localized: "Göster")
    /// Source label on alerts that arrived through a `notchhub://` URL (any app or web page can open one).
    static let externalSourceLabel = String(localized: "Harici")
    static let urlRateLimitCapacity = 10
    static let urlRateLimitWindow: TimeInterval = 60

    enum Source: String, Sendable {
        case url
        case socket
        case test
    }

    struct ReceivedAlert: Equatable, Sendable {
        let title: String
        let style: ExternalAlertStyle
        let source: Source
        let receivedAt: Date
    }

    enum Rejection: Error, Equatable {
        case disabled
        case urlAlertsDisabled
        case rateLimited
        case blocked
        case invalid(ExternalRequestError)

        var message: String {
            switch self {
            case .disabled: "external alerts are disabled in NotchHub settings"
            case .urlAlertsDisabled: "URL alerts are disabled in NotchHub settings; use the local socket"
            case .rateLimited: "rate limited, alert dropped"
            case .blocked: "alerts are paused"
            case .invalid(let error): error.message
            }
        }
    }

    private enum Keys {
        static let enabled = "Integrations.enabled"
        static let urlAlertsEnabled = "Integrations.urlAlertsEnabled"
        static let countDay = "Integrations.countDay"
        static let count = "Integrations.count"
        static let lastTitle = "Integrations.lastTitle"
        static let lastStyle = "Integrations.lastStyle"
        static let lastSource = "Integrations.lastSource"
        static let lastDate = "Integrations.lastDate"
    }

    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let socketServer: any IntegrationsSocketServing
    @ObservationIgnored private let system: any IntegrationsSystem
    @ObservationIgnored private var rateLimiter: IntegrationsRateLimiter
    @ObservationIgnored private var urlRateLimiter: IntegrationsRateLimiter
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Integrations")

    /// Absolute path of the Unix domain socket.
    let socketPath: String

    private(set) var socketState: IntegrationsSocketState = .stopped
    private(set) var lastAlert: ReceivedAlert?
    private(set) var dailyCount: IntegrationsDailyCount
    private(set) var droppedCount = 0

    /// Integrator hook: return `false` while global alerts are off or paused.
    @ObservationIgnored var shouldPostAlert: (@MainActor () -> Bool)?
    /// Integrator hook for `notchhub://open?module=…`.
    @ObservationIgnored var onOpenModule: (@MainActor (IntegrationsOpenTarget) -> Void)?

    /// Persisted "accept external alerts" toggle; starts or stops the socket while running.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Keys.enabled)
            guard isRunning else { return }
            isEnabled ? startSocket() : stopSocket()
        }
    }

    /// Persisted "allow alerts via web/URL" toggle. Off leaves only the local socket/CLI.
    var urlAlertsEnabled: Bool {
        didSet { defaults.set(urlAlertsEnabled, forKey: Keys.urlAlertsEnabled) }
    }

    init(
        alerts: NotchAlertCenter,
        defaults: UserDefaults = .standard,
        socketServer: any IntegrationsSocketServing = IntegrationsSocketServer(),
        system: (any IntegrationsSystem)? = nil,
        socketPath: String? = nil,
        calendar: Calendar = .current,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.alerts = alerts
        self.defaults = defaults
        self.socketServer = socketServer
        self.system = system ?? LiveIntegrationsSystem()
        self.socketPath = socketPath ?? Self.defaultSocketPath()
        self.calendar = calendar
        self.now = now
        rateLimiter = IntegrationsRateLimiter()
        urlRateLimiter = IntegrationsRateLimiter(capacity: Self.urlRateLimitCapacity, window: Self.urlRateLimitWindow)
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        urlAlertsEnabled = defaults.object(forKey: Keys.urlAlertsEnabled) as? Bool ?? true
        dailyCount = Self.loadDailyCount(from: defaults, calendar: calendar, now: now())
        lastAlert = Self.loadLastAlert(from: defaults)
    }

    // MARK: - Derived state

    var countToday: Int { dailyCount.count(at: now(), calendar: calendar) }

    var isListening: Bool { socketState == .listening }

    var isZshHookBundled: Bool { system.bundledZshHookPath != nil }

    /// One line for `~/.zshrc`.
    var zshSetupLine: String {
        let path = system.bundledZshHookPath ?? Self.zshHookPlaceholderPath
        return "source \(Self.shellQuoted(path))"
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        if isEnabled { startSocket() }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopSocket()
    }

    // MARK: - Entry points

    /// Call from `application(_:open:)`. Returns `true` when the URL was a valid, accepted request.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme?.lowercased() == ExternalRequestParser.scheme else { return false }
        switch process(ExternalRequestParser.parse(url: url), source: .url) {
        case .success: return true
        case .failure: return false
        }
    }

    /// Socket entry point: one JSON request in, one JSON reply line out.
    func handle(jsonLine: String) -> String {
        Self.reply(for: process(ExternalRequestParser.parse(jsonLine: jsonLine), source: .socket))
    }

    func sendTestAlert() {
        let request = ExternalAlertRequest(
            title: String(localized: "NotchHub entegrasyonları çalışıyor"),
            subtitle: String(localized: "Ayarlar'dan test uyarısı"),
            style: .success,
            systemImage: "checkmark.seal.fill",
            autoDismissAfter: NotchAlert.defaultDuration,
            coalescingKey: ExternalAlertSanitizer.keyNamespace + "test",
            openURL: nil,
            command: nil
        )
        post(request, source: .test)
    }

    func copyZshSetupLine() {
        system.copyToPasteboard(zshSetupLine)
    }

    // MARK: - Processing

    @discardableResult
    func process(_ outcome: ExternalRequestParser.Outcome, source: Source) -> Result<[String], Rejection> {
        guard isEnabled else { return reject(.disabled, source: source) }
        // Every request costs a token, so floods of invalid input are throttled too.
        guard rateLimiter.allow(at: now()) else { return reject(.rateLimited, source: source) }
        if source == .url, !urlRateLimiter.allow(at: now()) { return reject(.rateLimited, source: source) }
        let parsed: ExternalParseResult
        switch outcome {
        case .success(let value): parsed = value
        case .failure(let error): return reject(.invalid(error), source: source)
        }
        parsed.warnings.forEach { warning in
            logger.notice("External request (\(source.rawValue, privacy: .public)): \(warning, privacy: .public)")
        }

        switch parsed.request {
        case .open(let target):
            logger.info("External open request: \(target.rawValue, privacy: .public)")
            onOpenModule?(target)
        case .alert(let request):
            if source == .url, !urlAlertsEnabled { return reject(.urlAlertsDisabled, source: source) }
            guard shouldPostAlert?() ?? true else { return reject(.blocked, source: source) }
            post(request, source: source)
        }
        return .success(parsed.warnings)
    }

    private func post(_ request: ExternalAlertRequest, source: Source) {
        let symbol = system.symbolExists(request.systemImage) ? request.systemImage : ExternalAlertSanitizer.fallbackSymbol
        let action = alertAction(for: request.openURL)
        alerts.post(NotchAlert(
            module: nil,
            systemImage: symbol,
            title: request.title,
            subtitle: request.subtitle,
            style: request.style.alertStyle,
            coalescingKey: request.coalescingKey,
            autoDismissAfter: request.autoDismissAfter,
            actionTitle: action?.title,
            action: action?.perform,
            appName: source == .url ? Self.externalSourceLabel : nil
        ))
        record(ReceivedAlert(title: request.title, style: request.style, source: source, receivedAt: now()))
        logger.info("External alert posted via \(source.rawValue, privacy: .public)")
    }

    /// Web URLs open in the browser; file URLs are only revealed in Finder so a click never launches a binary.
    private func alertAction(for url: URL?) -> (title: String, perform: @MainActor () -> Void)? {
        guard let url else { return nil }
        let system = system
        if url.isFileURL {
            return (Self.revealActionTitle, { system.revealInFinder(url) })
        }
        return (Self.openActionTitle, { system.open(url) })
    }

    private func reject(_ rejection: Rejection, source: Source) -> Result<[String], Rejection> {
        if rejection == .rateLimited { droppedCount += 1 }
        logger.notice("External request rejected (\(source.rawValue, privacy: .public)): \(rejection.message, privacy: .public)")
        return .failure(rejection)
    }

    private func record(_ alert: ReceivedAlert) {
        lastAlert = alert
        dailyCount = dailyCount.incremented(at: alert.receivedAt, calendar: calendar)
        defaults.set(dailyCount.day.timeIntervalSinceReferenceDate, forKey: Keys.countDay)
        defaults.set(dailyCount.count, forKey: Keys.count)
        defaults.set(alert.title, forKey: Keys.lastTitle)
        defaults.set(alert.style.rawValue, forKey: Keys.lastStyle)
        defaults.set(alert.source.rawValue, forKey: Keys.lastSource)
        defaults.set(alert.receivedAt.timeIntervalSinceReferenceDate, forKey: Keys.lastDate)
    }

    // MARK: - Socket

    private func startSocket() {
        socketState = .starting
        socketServer.start(
            path: socketPath,
            onState: { [weak self] state in
                Task { @MainActor in self?.updateSocketState(state) }
            },
            onLine: { [weak self] line in
                self?.handle(jsonLine: line) ?? Self.reply(for: .failure(.disabled))
            }
        )
    }

    private func stopSocket() {
        socketServer.stop()
        socketState = .stopped
    }

    private func updateSocketState(_ state: IntegrationsSocketState) {
        // Late callbacks from a server that was already stopped must not resurrect the state.
        guard isRunning, isEnabled else { return }
        socketState = state
    }

    // MARK: - Helpers

    static func reply(for result: Result<[String], Rejection>) -> String {
        let object: [String: Any] = switch result {
        case .success(let warnings): ["ok": true, "warnings": warnings]
        case .failure(let rejection): ["ok": false, "error": rejection.message]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return #"{"ok":false}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Single-quoted for POSIX shells; embedded quotes become `'\''`.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    static func defaultSocketPath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return base.appending(path: appSupportFolder).appending(path: socketFileName).path
    }

    private static func loadDailyCount(from defaults: UserDefaults, calendar: Calendar, now: Date) -> IntegrationsDailyCount {
        guard let day = defaults.object(forKey: Keys.countDay) as? Double else {
            return .empty(at: now, calendar: calendar)
        }
        return IntegrationsDailyCount(
            day: Date(timeIntervalSinceReferenceDate: day),
            count: max(defaults.integer(forKey: Keys.count), 0)
        )
    }

    private static func loadLastAlert(from defaults: UserDefaults) -> ReceivedAlert? {
        guard let title = defaults.string(forKey: Keys.lastTitle),
              let date = defaults.object(forKey: Keys.lastDate) as? Double
        else { return nil }
        return ReceivedAlert(
            title: title,
            style: defaults.string(forKey: Keys.lastStyle).flatMap(ExternalAlertStyle.init(rawValue:)) ?? .info,
            source: defaults.string(forKey: Keys.lastSource).flatMap(Source.init(rawValue:)) ?? .url,
            receivedAt: Date(timeIntervalSinceReferenceDate: date)
        )
    }
}
