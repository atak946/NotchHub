import Foundation
import Observation
import OSLog

/// The last banner the mirror showed in the notch, for the Status tile.
struct MirroredNotification: Equatable, Sendable {
    let title: String
    let appName: String
    let date: Date
}

/// Mirrors macOS notification banners into the notch and (optionally) closes the native banner.
/// Reads Notification Center via Accessibility: an AXObserver gives ~0.3 s latency, polling is the safety net.
@MainActor
@Observable
final class NotificationMirrorService {
    /// Safety-net poll while no banner window exists.
    static let idlePollInterval: Duration = .seconds(1)
    /// Faster poll while Notification Center shows a banner window (fallback if AX events are missed).
    static let activePollInterval: Duration = .milliseconds(250)
    static let untrustedRecheckInterval: Duration = .seconds(10)
    static let alertDuration: Duration = .seconds(6)
    static let maxSeenIDs = 200

    private enum Keys {
        static let isEnabled = "Insights.mirrorEnabled"
        static let showsMessageText = "Insights.mirrorShowsMessageText"
        static let hidesNativeBanners = "Insights.mirrorHidesNativeBanners"
        static let scope = "Insights.mirrorScope"
        static let keywords = "Insights.mirrorKeywords"
    }

    private(set) var lastMirrored: MirroredNotification?
    private(set) var isRunning = false

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            if !isEnabled { resetBaseline() }
        }
    }

    var showsMessageText: Bool {
        didSet { defaults.set(showsMessageText, forKey: Keys.showsMessageText) }
    }

    var hidesNativeBanners: Bool {
        didSet { defaults.set(hidesNativeBanners, forKey: Keys.hidesNativeBanners) }
    }

    var scope: NotificationMirrorScope {
        didSet { defaults.set(scope.rawValue, forKey: Keys.scope) }
    }

    var keywords: [String] {
        didSet {
            let valid = NotificationMirrorPolicy.normalizedKeywords(keywords)
            if valid != keywords { keywords = valid }
            defaults.set(valid, forKey: Keys.keywords)
        }
    }

    /// Wired by ModuleServices to the global "alerts on and not paused" state. Unset means "cannot post",
    /// so nothing is ever dismissed without being shown in the notch.
    @ObservationIgnored var shouldPostAlert: (@MainActor () -> Bool)?

    var isAccessibilityTrusted: Bool { permission.isTrusted }

    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let permission: AccessibilityPermission
    @ObservationIgnored private let reader: any NotificationBannerReading
    @ObservationIgnored private let observer: (any NotificationCenterEventObserving)?
    @ObservationIgnored private let activator: any InsightsAppActivating
    @ObservationIgnored private let ledger: NotificationMirrorLedger
    @ObservationIgnored private let clock: any InsightsClock
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var seen = BoundedIDSet(capacity: NotificationMirrorService.maxSeenIDs)
    @ObservationIgnored private var hasBaseline = false
    @ObservationIgnored private var hasBannerWindow = false
    @ObservationIgnored private var isPolling = false
    @ObservationIgnored private var needsRepoll = false
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Insights")

    init(
        alerts: NotchAlertCenter,
        permission: AccessibilityPermission,
        reader: any NotificationBannerReading = AXNotificationBannerReader(),
        observer: (any NotificationCenterEventObserving)? = nil,
        activator: any InsightsAppActivating = SystemInsightsAppActivator(),
        ledger: NotificationMirrorLedger = NotificationMirrorLedger(),
        clock: any InsightsClock = SystemInsightsClock(),
        defaults: UserDefaults = .standard
    ) {
        self.alerts = alerts
        self.permission = permission
        self.reader = reader
        self.observer = observer
        self.activator = activator
        self.ledger = ledger
        self.clock = clock
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        showsMessageText = defaults.object(forKey: Keys.showsMessageText) as? Bool ?? true
        hidesNativeBanners = defaults.object(forKey: Keys.hidesNativeBanners) as? Bool ?? true
        scope = defaults.string(forKey: Keys.scope).flatMap(NotificationMirrorScope.init(rawValue:)) ?? .allApps
        keywords = NotificationMirrorPolicy.normalizedKeywords(
            defaults.stringArray(forKey: Keys.keywords) ?? NotificationMirrorPolicy.defaultKeywords
        )
    }

    // MARK: - Lifecycle

    func start() {
        guard pollTask == nil else { return }
        isRunning = true
        let clock = self.clock
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                let delay = self.nextDelay()
                try? await clock.sleep(for: delay)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        observer?.detach()
        isRunning = false
        resetBaseline()
    }

    /// One read of Notification Center; repeats once if an AX event arrived meanwhile.
    func poll() async {
        guard !isPolling else {
            needsRepoll = true
            return
        }
        isPolling = true
        defer { isPolling = false }
        repeat {
            needsRepoll = false
            await pollOnce()
        } while needsRepoll
    }

    func open(app: String) {
        activator.activate(appNamed: app)
    }

    // MARK: - Keywords

    func addKeyword(_ keyword: String) {
        keywords = keywords + [keyword]
    }

    func removeKeyword(_ keyword: String) {
        keywords = keywords.filter { $0 != keyword }
    }

    // MARK: - Private

    private func pollOnce() async {
        guard isEnabled else { return }
        guard permission.refresh() else {
            observer?.detach()
            resetBaseline()
            return
        }
        observer?.attach { [weak self] in
            guard let self, self.isRunning else { return }
            Task { await self.poll() }
        }
        let reader = self.reader
        guard let snapshot = await Task.detached(operation: { reader.readSnapshot() }).value else {
            logger.debug("Notification Center banners unavailable")
            return
        }
        await apply(snapshot)
    }

    private func apply(_ snapshot: NotificationCenterSnapshot) async {
        hasBannerWindow = snapshot.hasBannerWindow
        let fresh = snapshot.banners.filter { seen.insert($0.id) }
        guard hasBaseline else {
            hasBaseline = true
            return
        }
        let canPost = shouldPostAlert?() ?? false
        for banner in fresh {
            let decision = NotificationMirrorPolicy.decision(
                for: banner, scope: scope, keywords: keywords, canPost: canPost, hidesNative: hidesNativeBanners
            )
            guard case .mirror(let dismissNative) = decision else { continue }
            post(banner)
            if dismissNative { await dismiss(banner) }
        }
    }

    private func post(_ banner: NotificationBanner) {
        let content = NotificationMirrorPolicy.content(
            for: banner, keywords: keywords, showsMessageText: showsMessageText
        )
        let app = banner.app
        var openAction: (@MainActor () -> Void)?
        if NotificationMirrorPolicy.canOpen(app: app) {
            openAction = { [weak self] in self?.open(app: app) }
        }
        let now = clock.now
        if let key = content.messagingKey {
            ledger.record(appKey: key, at: now)
        }
        lastMirrored = MirroredNotification(title: content.title, appName: MessagingApp.displayName(for: app), date: now)
        alerts.post(NotchAlert(
            module: .status,
            systemImage: content.systemImage,
            title: content.title,
            subtitle: content.subtitle,
            style: .info,
            coalescingKey: content.coalescingKey,
            autoDismissAfter: Self.alertDuration,
            actionTitle: openAction == nil ? nil : "Aç",
            action: openAction,
            appBundleID: KnownApps.bundleID(forName: app),
            appName: MessagingApp.displayName(for: app),
            sender: content.messagingKey == nil ? nil : content.title
        ))
    }

    private func dismiss(_ banner: NotificationBanner) async {
        let reader = self.reader
        let id = banner.id
        let closed = await Task.detached(operation: { reader.dismiss(bannerID: id) }).value
        if !closed { logger.debug("Could not close a mirrored notification banner") }
    }

    private func resetBaseline() {
        seen.removeAll()
        hasBaseline = false
        hasBannerWindow = false
    }

    private func nextDelay() -> Duration {
        guard permission.isTrusted else { return Self.untrustedRecheckInterval }
        return hasBannerWindow ? Self.activePollInterval : Self.idlePollInterval
    }
}
