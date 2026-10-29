import Foundation
import Observation

/// Facade for the Insights feature: Dock unread badges (#11), notification mirroring and billable time tracking (#15).
/// Both need Accessibility; trust is only ever checked silently until the user asks to grant it.
@MainActor
@Observable
final class Insights {
    let permission: AccessibilityPermission
    let unread: UnreadBadgeMonitor
    let mirror: NotificationMirrorService
    let timeTracker: TimeTracker

    var isAccessibilityTrusted: Bool { permission.isTrusted }
    var hasCompactIndicator: Bool { unread.hasCompactIndicator }

    convenience init(alerts: NotchAlertCenter, defaults: UserDefaults = .standard) {
        self.init(
            alerts: alerts, defaults: defaults, trustChecker: SystemAccessibilityTrust(),
            bannerObserver: AXNotificationCenterObserver()
        )
    }

    init(
        alerts: NotchAlertCenter,
        defaults: UserDefaults,
        trustChecker: any AccessibilityTrustChecking,
        badgeReader: any DockBadgeReading = AXDockBadgeReader(),
        bannerReader: any NotificationBannerReading = AXNotificationBannerReader(),
        bannerObserver: (any NotificationCenterEventObserving)? = nil,
        activator: any InsightsAppActivating = SystemInsightsAppActivator(),
        probe: any ActivityProbing = SystemActivityProbe(),
        store: any TimeLedgerStoring = FileTimeLedgerStore.makeDefault(),
        clock: any InsightsClock = SystemInsightsClock(),
        calendar: Calendar = .autoupdatingCurrent,
        pasteboard: any InsightsPasteboard = SystemInsightsPasteboard()
    ) {
        let permission = AccessibilityPermission(checker: trustChecker)
        self.permission = permission
        let ledger = NotificationMirrorLedger()
        unread = UnreadBadgeMonitor(
            alerts: alerts, permission: permission, reader: badgeReader,
            activator: activator, clock: clock, defaults: defaults, mirrorLedger: ledger
        )
        mirror = NotificationMirrorService(
            alerts: alerts, permission: permission, reader: bannerReader, observer: bannerObserver,
            activator: activator, ledger: ledger, clock: clock, defaults: defaults
        )
        timeTracker = TimeTracker(
            alerts: alerts, permission: permission, probe: probe, store: store,
            clock: clock, calendar: calendar, pasteboard: pasteboard, defaults: defaults
        )
    }

    func start() {
        permission.refresh()
        unread.start()
        mirror.start()
        timeTracker.start()
    }

    func stop() {
        unread.stop()
        mirror.stop()
        timeTracker.stop()
    }

    /// Explicit user action only: prompts and opens System Settings › Privacy & Security › Accessibility.
    func requestAccessibilityAccess() {
        permission.requestAccess()
    }

    func refreshAccessibilityTrust() {
        permission.refresh()
    }
}
