import Foundation
import Observation
import OSLog

/// `CalendarEventSource` for Microsoft 365 / Outlook via Microsoft Graph, signed in with the OAuth device-code flow.
/// The new Outlook for Mac keeps its data to itself, so this reads the cloud calendar directly.
/// Tokens live in the Keychain; `UserDefaults` only holds the (public) client id, tenant and account name.
@MainActor
@Observable
final class MicrosoftGraphSource: CalendarEventSource {
    static let refreshInterval: TimeInterval = 5 * 60
    /// Synced window: start of today through this many days ahead (covers the service's lookahead).
    static let syncDays = 2
    /// Access tokens are refreshed this long before they expire.
    static let tokenExpiryMargin: TimeInterval = 120
    static let tokenSecretKey = "microsoft.tokens"
    static let accountID = "microsoft365.account"
    static let calendarID = "microsoft365.calendar"
    static let defaultAccountTitle = "Microsoft 365"
    static let calendarTitle = String(localized: "Outlook Calendar")
    static let calendarColor = CalendarColor(red: 0.0, green: 0.47, blue: 0.84)

    enum Keys {
        static let clientID = "calendar.microsoft.clientID"
        static let tenant = "calendar.microsoft.tenant"
        static let username = "calendar.microsoft.username"
    }

    let sourceID = "microsoft365"
    let sourceName = "Microsoft 365"
    let sourceSystemImage = "envelope.fill"

    private(set) var state: MicrosoftSignInState
    private(set) var statusMessage: String?
    private(set) var lastSync: Date?
    private(set) var isSyncing = false

    var clientID: String {
        didSet { defaults.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.clientID) }
    }

    var tenant: String {
        didSet { defaults.set(tenant.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.tenant) }
    }

    var configuration: MicrosoftGraphConfiguration? {
        MicrosoftGraphConfiguration.validated(clientID: clientID, tenant: tenant)
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    var authorization: CalendarAuthorization {
        isSignedIn ? .authorized : .notDetermined
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secrets: any CalendarSecretStore
    @ObservationIgnored private let http: any CalendarHTTPClient
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Calendar")
    @ObservationIgnored private var tokens: MicrosoftTokenSet?
    @ObservationIgnored private var cachedEvents: [CalendarEvent] = []
    @ObservationIgnored private var changeHandler: (@MainActor () -> Void)?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var signInTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        secrets: any CalendarSecretStore = KeychainCalendarSecretStore(),
        http: any CalendarHTTPClient = URLSessionCalendarHTTPClient(),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.defaults = defaults
        self.secrets = secrets
        self.http = http
        self.now = now
        self.sleep = sleep
        clientID = defaults.string(forKey: Keys.clientID) ?? ""
        tenant = defaults.string(forKey: Keys.tenant) ?? MicrosoftGraphConfiguration.defaultTenant
        // The Keychain is only touched on first sync, so init never triggers a Keychain prompt.
        state = defaults.string(forKey: Keys.username).map { .signedIn(username: $0) } ?? .signedOut
    }

    // MARK: - CalendarEventSource

    func requestAccess() async -> CalendarAuthorization { authorization }

    func accounts() -> [CalendarAccount] {
        isSignedIn ? [context.account] : []
    }

    func calendars() -> [CalendarInfo] {
        isSignedIn ? [context.calendarInfo] : []
    }

    func events(from start: Date, to end: Date) throws -> [CalendarEvent] {
        if lastSync == nil, let statusMessage {
            throw MicrosoftAuthError.server(statusMessage)
        }
        return cachedEvents.filter { $0.start < end && $0.end > start }
    }

    func startObservingChanges(_ handler: @escaping @MainActor () -> Void) {
        changeHandler = handler
        pollTask?.cancel()
        let sleep = self.sleep
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                do { try await sleep(.seconds(Self.refreshInterval)) } catch { return }
            }
        }
    }

    func stopObservingChanges() {
        pollTask?.cancel()
        pollTask = nil
        changeHandler = nil
    }

    // MARK: - Sign-in

    /// Starts the device-code flow; progress is published through `state`.
    func signIn() {
        guard let configuration else {
            statusMessage = MicrosoftAuthError.notConfigured.localizedDescription
            return
        }
        signInTask?.cancel()
        statusMessage = nil
        state = .requestingCode
        signInTask = Task { [weak self] in
            await self?.runSignIn(configuration)
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        if !isSignedIn { state = .signedOut }
    }

    /// Removes tokens and cached events. `reason` is shown as a status line (no alert).
    func signOut(reason: String? = nil) {
        signInTask?.cancel()
        signInTask = nil
        secrets.removeSecret(for: Self.tokenSecretKey)
        defaults.removeObject(forKey: Keys.username)
        tokens = nil
        cachedEvents = []
        lastSync = nil
        state = .signedOut
        statusMessage = reason
        changeHandler?()
    }

    /// Fetches the calendar view now (also called every 5 minutes while observing).
    func refreshNow() async {
        guard isSignedIn, !isSyncing else { return }
        guard let configuration else {
            statusMessage = MicrosoftAuthError.notConfigured.localizedDescription
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let graphEvents = try await fetchEvents(configuration)
            guard isSignedIn else { return }
            cachedEvents = MicrosoftGraphEventMapper.events(from: graphEvents, context: context)
            lastSync = now()
            statusMessage = nil
            changeHandler?()
        } catch is CancellationError {
            return
        } catch let error as MicrosoftAuthError where error == .invalidGrant {
            logger.info("Microsoft 365 session expired")
            signOut(reason: error.localizedDescription)
        } catch MicrosoftGraphError.unauthorized {
            logger.info("Microsoft 365 token rejected after refresh")
            signOut(reason: MicrosoftAuthError.invalidGrant.localizedDescription)
        } catch {
            logger.error("Microsoft 365 sync failed: \(error.localizedDescription, privacy: .public)")
            statusMessage = String(localized: "Eşitleme başarısız: \(error.localizedDescription)")
            changeHandler?()
        }
    }

    // MARK: - Private

    private var context: CalendarSourceContext {
        let username: String? = if case let .signedIn(name) = state { name } else { nil }
        return CalendarSourceContext(
            idPrefix: sourceID,
            calendarID: Self.calendarID,
            calendarTitle: Self.calendarTitle,
            color: Self.calendarColor,
            account: CalendarAccount(id: Self.accountID, title: username ?? Self.defaultAccountTitle, kind: .outlook)
        )
    }

    private func flow(_ configuration: MicrosoftGraphConfiguration) -> MicrosoftDeviceCodeFlow {
        MicrosoftDeviceCodeFlow(configuration: configuration, http: http, now: now, sleep: sleep)
    }

    private var client: MicrosoftGraphCalendarClient {
        MicrosoftGraphCalendarClient(http: http)
    }

    private func runSignIn(_ configuration: MicrosoftGraphConfiguration) async {
        let flow = flow(configuration)
        do {
            let grant = try await flow.requestDeviceCode()
            try Task.checkCancellation()
            state = .awaitingUser(grant.prompt)
            let tokenSet = try await flow.pollForToken(grant)
            try Task.checkCancellation()
            try save(tokenSet)
            let username = (try? await client.userName(accessToken: tokenSet.accessToken)) ?? Self.defaultAccountTitle
            defaults.set(username, forKey: Keys.username)
            state = .signedIn(username: username)
            logger.info("Signed in to Microsoft 365")
            await refreshNow()
        } catch is CancellationError {
            if !isSignedIn { state = .signedOut }
        } catch {
            logger.error("Microsoft 365 sign-in failed: \(error.localizedDescription, privacy: .public)")
            state = .signedOut
            statusMessage = error.localizedDescription
        }
    }

    private func fetchEvents(_ configuration: MicrosoftGraphConfiguration) async throws -> [MicrosoftGraphEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now())
        let end = calendar.date(byAdding: .day, value: Self.syncDays, to: start) ?? start.addingTimeInterval(TimeInterval(Self.syncDays) * 86_400)
        let token = try await accessToken(configuration, forceRefresh: false)
        do {
            return try await client.calendarView(accessToken: token, from: start, to: end)
        } catch MicrosoftGraphError.unauthorized {
            let fresh = try await accessToken(configuration, forceRefresh: true)
            return try await client.calendarView(accessToken: fresh, from: start, to: end)
        }
    }

    private func accessToken(_ configuration: MicrosoftGraphConfiguration, forceRefresh: Bool) async throws -> String {
        guard let current = tokens ?? loadTokens() else { throw MicrosoftAuthError.invalidGrant }
        if !forceRefresh, current.expiresAt.addingTimeInterval(-Self.tokenExpiryMargin) > now() {
            return current.accessToken
        }
        guard let refreshToken = current.refreshToken else { throw MicrosoftAuthError.invalidGrant }
        let refreshed = try await flow(configuration).refresh(refreshToken)
        try save(refreshed)
        return refreshed.accessToken
    }

    private func loadTokens() -> MicrosoftTokenSet? {
        guard let json = secrets.secret(for: Self.tokenSecretKey) else { return nil }
        let loaded = try? JSONDecoder().decode(MicrosoftTokenSet.self, from: Data(json.utf8))
        tokens = loaded
        return loaded
    }

    private func save(_ tokenSet: MicrosoftTokenSet) throws {
        let data = try JSONEncoder().encode(tokenSet)
        try secrets.setSecret(String(decoding: data, as: UTF8.self), for: Self.tokenSecretKey)
        tokens = tokenSet
    }
}
