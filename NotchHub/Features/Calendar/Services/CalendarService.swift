import AppKit
import Foundation
import Observation
import OSLog

/// Owns calendar state for the notch: next meeting, rest of today, reminders, filters and grouping.
@MainActor
@Observable
final class CalendarService {
    static let reminderLeadTimeOptions: [TimeInterval] = [0, 60, 5 * 60, 10 * 60, 15 * 60]
    static let defaultReminderLeadTime: TimeInterval = 5 * 60
    static let defaultGrouping: CalendarGrouping = .none
    static let refreshInterval: TimeInterval = 60
    /// Small offset after the minute boundary so the tick lands just past e.g. 09:55:00.
    static let tickSlack: TimeInterval = 0.25
    /// Fired reminders are remembered this long past the event start, then pruned.
    static let firedRetention: TimeInterval = 24 * 60 * 60

    private static let privacySettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
    private static let internetAccountsURL = "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension"
    private static let calendarBundleID = "com.apple.iCal"
    private static let zoomProbeURL = "zoommtg://zoom.us"

    enum Keys {
        static let reminderLeadTime = "calendar.reminderLeadTime"
        static let hiddenCalendarIDs = "calendar.hiddenCalendarIDs"
        static let grouping = "calendar.grouping"
    }

    /// `.authorized` when at least one source can deliver events; otherwise the primary (EventKit) source's state.
    private(set) var authorization: CalendarAuthorization
    private(set) var nextEvent: CalendarEvent?
    /// Remaining (not ended) events of today, all-day first, including `nextEvent` when it is today.
    private(set) var todayEvents: [CalendarEvent] = []
    private(set) var accounts: [CalendarAccount] = []
    private(set) var calendars: [CalendarInfo] = []
    /// Per-source "N events today" lines, updated on every refresh.
    private(set) var sourceDiagnostics: [CalendarSourceDiagnostic] = []

    /// Seconds before start at which `onReminder` fires. 0 disables reminders.
    var reminderLeadTime: TimeInterval {
        didSet { defaults.set(reminderLeadTime, forKey: Keys.reminderLeadTime) }
    }

    /// Calendars excluded from the next event, today list and reminders.
    var hiddenCalendarIDs: Set<String> {
        didSet {
            defaults.set(hiddenCalendarIDs.sorted(), forKey: Keys.hiddenCalendarIDs)
            applyFilters(at: now())
        }
    }

    var grouping: CalendarGrouping {
        didSet { defaults.set(grouping.rawValue, forKey: Keys.grouping) }
    }

    /// Fired once per event when the clock crosses `start − reminderLeadTime`. Integrator opens the notch here.
    @ObservationIgnored var onReminder: (@MainActor (CalendarEvent) -> Void)?

    /// Aggregated sources; the first one is the primary (EventKit) source and wins dedupe ties.
    @ObservationIgnored let sources: [any CalendarEventSource]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let calendar = Calendar.current
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Calendar")
    @ObservationIgnored private var allEvents: [CalendarEvent] = []
    @ObservationIgnored private var visibleEvents: [CalendarEvent] = []
    /// Event id → start date, for reminders that already fired.
    @ObservationIgnored private var firedReminders: [String: Date] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    /// Default production setup: EventKit plus ICS feeds and Microsoft 365 (both inactive until configured).
    convenience init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = Date.init) {
        let secrets = KeychainCalendarSecretStore()
        let http = URLSessionCalendarHTTPClient()
        self.init(
            sources: [
                EventKitCalendarSource(),
                ICSFeedSource(defaults: defaults, secrets: secrets, http: http, now: now),
                MicrosoftGraphSource(defaults: defaults, secrets: secrets, http: http, now: now),
            ],
            defaults: defaults,
            now: now
        )
    }

    convenience init(
        source: any CalendarEventSource,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.init(sources: [source], defaults: defaults, now: now)
    }

    init(
        sources: [any CalendarEventSource],
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.sources = sources
        self.defaults = defaults
        self.now = now
        authorization = Self.aggregateAuthorization(of: sources)

        let storedLead = defaults.object(forKey: Keys.reminderLeadTime) as? Double
        reminderLeadTime = storedLead.flatMap { Self.reminderLeadTimeOptions.contains($0) ? $0 : nil }
            ?? Self.defaultReminderLeadTime
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: Keys.hiddenCalendarIDs) ?? [])
        grouping = defaults.string(forKey: Keys.grouping).flatMap(CalendarGrouping.init) ?? Self.defaultGrouping
    }

    var isRunning: Bool { refreshTask != nil }

    /// Authorization of the primary (EventKit) source, for the settings status row.
    var primaryAuthorization: CalendarAuthorization {
        sources.first?.authorization ?? .notDetermined
    }

    var icsFeedSource: ICSFeedSource? {
        sources.lazy.compactMap { $0 as? ICSFeedSource }.first
    }

    var microsoftSource: MicrosoftGraphSource? {
        sources.lazy.compactMap { $0 as? MicrosoftGraphSource }.first
    }

    // MARK: - Lifecycle

    /// Requests access lazily (first run only), then refreshes every minute and on store changes.
    func start() {
        guard refreshTask == nil else { return }
        for source in sources {
            source.startObservingChanges { [weak self] in
                self?.refresh()
            }
        }
        refreshTask = Task { [weak self] in
            await self?.ensureAccess()
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                let delay = self.delayUntilNextTick()
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        for source in sources {
            source.stopObservingChanges()
        }
    }

    /// Re-reads every source's calendars and events (a failing source is skipped), dedupes, then evaluates reminders.
    func refresh() {
        let date = now()
        let aggregate = Self.aggregateAuthorization(of: sources)
        if aggregate != authorization { authorization = aggregate }
        guard authorization == .authorized else {
            clearState()
            update(\.sourceDiagnostics, to: sources.enumerated().map { inactiveDiagnostic(for: $1, index: $0) })
            return
        }
        let snapshot = collect(at: date)
        update(\.accounts, to: snapshot.accounts)
        update(\.calendars, to: snapshot.calendars)
        update(\.sourceDiagnostics, to: snapshot.diagnostics)
        allEvents = CalendarEventDeduplicator.deduplicate(snapshot.events)
        applyFilters(at: date)
        fireDueReminders(at: date)
    }

    // MARK: - Filters & grouping

    func isCalendarHidden(_ calendarID: String) -> Bool {
        hiddenCalendarIDs.contains(calendarID)
    }

    func setCalendar(_ calendarID: String, visible: Bool) {
        hiddenCalendarIDs = visible ? hiddenCalendarIDs.subtracting([calendarID]) : hiddenCalendarIDs.union([calendarID])
    }

    func calendars(for account: CalendarAccount) -> [CalendarInfo] {
        calendars.filter { $0.accountID == account.id }
    }

    /// Today's remaining events grouped by the current `grouping`, optionally excluding one event (e.g. the card).
    func groupedTodayEvents(excluding excludedID: CalendarEvent.ID? = nil) -> [CalendarEventGroup] {
        let events = todayEvents.filter { $0.id != excludedID }
        return CalendarEventGrouper.groups(for: events, by: grouping)
    }

    // MARK: - Actions

    func requestAccess() {
        Task { [weak self] in
            await self?.ensureAccess()
            self?.refresh()
        }
    }

    func join(_ event: CalendarEvent) {
        guard let link = event.meetingLink else {
            logger.info("Join requested for event without a meeting link")
            return
        }
        let url = MeetingLinkParser.launchURL(for: link, isZoomAppInstalled: isZoomAppInstalled)
        open(url, what: "\(link.provider.displayName) meeting")
    }

    func openCalendarApp() {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.calendarBundleID) else {
            logger.error("Calendar app not found")
            return
        }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    func openPrivacySettings() {
        guard let url = URL(string: Self.privacySettingsURL) else { return }
        open(url, what: "privacy settings")
    }

    /// System Settings › Internet Accounts, where a Microsoft Exchange account makes Outlook events visible to EventKit.
    func openInternetAccounts() {
        guard let url = URL(string: Self.internetAccountsURL) else { return }
        open(url, what: "Internet Accounts settings")
    }

    // MARK: - Private

    private func ensureAccess() async {
        for source in sources where source.authorization == .notDetermined {
            _ = await source.requestAccess()
        }
        authorization = Self.aggregateAuthorization(of: sources)
    }

    static func aggregateAuthorization(of sources: [any CalendarEventSource]) -> CalendarAuthorization {
        if sources.contains(where: { $0.authorization == .authorized }) { return .authorized }
        return sources.first?.authorization ?? .notDetermined
    }

    private struct Snapshot {
        var accounts: [CalendarAccount] = []
        var calendars: [CalendarInfo] = []
        var events: [CalendarEvent] = []
        var diagnostics: [CalendarSourceDiagnostic] = []
    }

    private func collect(at date: Date) -> Snapshot {
        let interval = CalendarSchedule.fetchInterval(at: date, calendar: calendar)
        let today = DateInterval(start: calendar.startOfDay(for: date), end: CalendarSchedule.endOfDay(for: date, calendar: calendar))
        var snapshot = Snapshot()
        var seenAccounts = Set<String>()
        var seenCalendars = Set<String>()
        for (index, source) in sources.enumerated() {
            guard source.authorization == .authorized else {
                snapshot.diagnostics.append(inactiveDiagnostic(for: source, index: index))
                continue
            }
            snapshot.accounts += source.accounts().filter { seenAccounts.insert($0.id).inserted }
            snapshot.calendars += source.calendars().filter { seenCalendars.insert($0.id).inserted }
            do {
                let events = try source.events(from: interval.start, to: interval.end)
                snapshot.events += events
                let todayCount = events.filter { $0.start < today.end && $0.end > today.start }.count
                snapshot.diagnostics.append(diagnostic(for: source, index: index, eventsToday: todayCount, message: source.statusMessage))
            } catch {
                logger.error("Calendar source \(source.sourceID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                snapshot.diagnostics.append(diagnostic(for: source, index: index, eventsToday: 0, message: error.localizedDescription))
            }
        }
        return snapshot
    }

    private func diagnostic(
        for source: any CalendarEventSource,
        index: Int,
        eventsToday: Int,
        message: String?
    ) -> CalendarSourceDiagnostic {
        CalendarSourceDiagnostic(
            id: "\(index).\(source.sourceID)",
            name: source.sourceName,
            systemImage: source.sourceSystemImage,
            isActive: true,
            eventsToday: eventsToday,
            message: message
        )
    }

    private func inactiveDiagnostic(for source: any CalendarEventSource, index: Int) -> CalendarSourceDiagnostic {
        let message = source.statusMessage ?? (source.authorization == .denied ? "Erişim yok" : "Bağlı değil")
        return CalendarSourceDiagnostic(
            id: "\(index).\(source.sourceID)",
            name: source.sourceName,
            systemImage: source.sourceSystemImage,
            isActive: false,
            eventsToday: 0,
            message: message
        )
    }

    /// Assigns only on change so observers are not invalidated every minute.
    private func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<CalendarService, Value>, to value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    private func applyFilters(at date: Date) {
        visibleEvents = CalendarSchedule.visible(allEvents, hiddenCalendarIDs: hiddenCalendarIDs)
        let next = CalendarSchedule.nextEvent(in: visibleEvents, at: date)
        let today = CalendarSchedule.remainingToday(in: visibleEvents, at: date, calendar: calendar)
        if next != nextEvent { nextEvent = next }
        if today != todayEvents { todayEvents = today }
    }

    private func fireDueReminders(at date: Date) {
        firedReminders = firedReminders.filter { date.timeIntervalSince($0.value) < Self.firedRetention }
        let due = CalendarSchedule.dueReminders(
            in: visibleEvents,
            at: date,
            leadTime: reminderLeadTime,
            alreadyFired: Set(firedReminders.keys)
        )
        for event in due {
            firedReminders[event.id] = event.start
            logger.info("Reminder for upcoming event")
            onReminder?(event)
        }
    }

    private func clearState() {
        allEvents = []
        visibleEvents = []
        if nextEvent != nil { nextEvent = nil }
        if !todayEvents.isEmpty { todayEvents = [] }
        if !accounts.isEmpty { accounts = [] }
        if !calendars.isEmpty { calendars = [] }
    }

    private func delayUntilNextTick() -> TimeInterval {
        let seconds = now().timeIntervalSinceReferenceDate
        let remainder = seconds.truncatingRemainder(dividingBy: Self.refreshInterval)
        return Self.refreshInterval - remainder + Self.tickSlack
    }

    private var isZoomAppInstalled: Bool {
        guard let probe = URL(string: Self.zoomProbeURL) else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
    }

    private func open(_ url: URL, what: String) {
        if !NSWorkspace.shared.open(url) {
            logger.error("Could not open \(what, privacy: .public)")
        }
    }
}
