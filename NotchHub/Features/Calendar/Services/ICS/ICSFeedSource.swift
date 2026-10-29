import Foundation
import Observation
import OSLog

/// `CalendarEventSource` for published ICS / webcal feeds (e.g. Outlook on the web › Publish a calendar).
/// Feed URLs grant read access, so they are kept in the Keychain; `UserDefaults` only holds ids, names and colors.
@MainActor
@Observable
final class ICSFeedSource: CalendarEventSource {
    static let refreshInterval: TimeInterval = 5 * 60
    static let maxFeedBytes = 20 * 1024 * 1024
    static let secretKeyPrefix = "ics.feed."
    private static let requestTimeout: TimeInterval = 30
    private static let calendarMarker = "BEGIN:VCALENDAR"
    private static let defaultOutlookName = String(localized: "Outlook calendar")
    private static let defaultName = String(localized: "Calendar feed")

    enum FeedError: Error, Equatable, LocalizedError {
        case missingURL
        case http(Int)
        case notACalendar
        case tooLarge
        case allFeedsFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingURL: String(localized: "Akış bağlantısı Anahtar Zinciri'nde yok. Akışı kaldırıp yeniden ekleyin.")
            case .http(401), .http(403): String(localized: "Erişim reddedildi (HTTP 401/403). Takvimi yeniden yayınlayıp bağlantıyı güncelleyin.")
            case .http(404): String(localized: "Akış bulunamadı (HTTP 404). Takvim artık yayında olmayabilir.")
            case let .http(code): String(localized: "Sunucu hatası (HTTP \(code)).")
            case .notACalendar: String(localized: "Bağlantı bir iCalendar (.ics) dosyası döndürmedi.")
            case .tooLarge: String(localized: "Akış çok büyük.")
            case let .allFeedsFailed(message): message
            }
        }
    }

    let sourceID = "ics"
    let sourceName = String(localized: "ICS feeds")
    let sourceSystemImage = "link"

    private(set) var feeds: [ICSFeed]
    private(set) var feedStatus: [String: ICSFeedStatus] = [:]
    private(set) var isSyncing = false

    var statusMessage: String? {
        let failures = feeds.compactMap { feed in feedStatus[feed.id]?.errorMessage.map { "\(feed.name): \($0)" } }
        return failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    var authorization: CalendarAuthorization {
        feeds.isEmpty ? .notDetermined : .authorized
    }

    @ObservationIgnored private let store: ICSFeedStore
    @ObservationIgnored private let secrets: any CalendarSecretStore
    @ObservationIgnored private let http: any CalendarHTTPClient
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Calendar")
    @ObservationIgnored private var cache: [String: CachedFeed] = [:]
    @ObservationIgnored private var changeHandler: (@MainActor () -> Void)?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        secrets: any CalendarSecretStore = KeychainCalendarSecretStore(),
        http: any CalendarHTTPClient = URLSessionCalendarHTTPClient(),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        store = ICSFeedStore(defaults: defaults)
        self.secrets = secrets
        self.http = http
        self.now = now
        self.sleep = sleep
        feeds = store.load()
    }

    // MARK: - CalendarEventSource

    func requestAccess() async -> CalendarAuthorization { authorization }

    func accounts() -> [CalendarAccount] {
        feeds.map(\.account)
    }

    func calendars() -> [CalendarInfo] {
        feeds.map { context(for: $0).calendarInfo }
    }

    func events(from start: Date, to end: Date) throws -> [CalendarEvent] {
        guard end > start else { return [] }
        let window = DateInterval(start: start, end: end)
        let synced = feeds.filter { cache[$0.id] != nil }
        if synced.isEmpty, let message = statusMessage {
            throw FeedError.allFeedsFailed(message)
        }
        return synced.flatMap { feed in
            cache[feed.id].map { ICSEventExpander.events(in: $0.data, window: window, context: context(for: feed)) } ?? []
        }
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

    // MARK: - Feed management

    /// Validates the link, stores it in the Keychain and starts syncing the new feed.
    @discardableResult
    func addFeed(name: String, urlString: String) throws -> ICSFeed {
        let url = try ICSFeedURL.normalized(urlString)
        let kind = ICSFeedURL.accountKind(for: url)
        let id = UUID().uuidString
        try secrets.setSecret(url.absoluteString, for: Self.secretKey(for: id))
        let feed = ICSFeed(
            id: id,
            name: Self.feedName(name, kind: kind, url: url),
            colorIndex: feeds.count,
            kindRawValue: kind.rawValue
        )
        feeds.append(feed)
        store.save(feeds)
        logger.info("Added ICS feed")
        Task { [weak self] in
            await self?.sync(feed)
            self?.changeHandler?()
        }
        return feed
    }

    func removeFeed(id: ICSFeed.ID) {
        guard feeds.contains(where: { $0.id == id }) else { return }
        feeds.removeAll { $0.id == id }
        store.save(feeds)
        secrets.removeSecret(for: Self.secretKey(for: id))
        cache[id] = nil
        feedStatus[id] = nil
        changeHandler?()
    }

    func renameFeed(id: ICSFeed.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = feeds.firstIndex(where: { $0.id == id }), feeds[index].name != trimmed else { return }
        feeds[index].name = trimmed
        store.save(feeds)
        changeHandler?()
    }

    /// Downloads and parses a link without saving it ("Found 23 events").
    func testFeed(urlString: String) async -> ICSFeedTestResult {
        do {
            let url = try ICSFeedURL.normalized(urlString)
            return try await testResult(for: url)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func testFeed(id: ICSFeed.ID) async -> ICSFeedTestResult {
        guard let stored = secrets.secret(for: Self.secretKey(for: id)) else {
            return .failure(FeedError.missingURL.localizedDescription)
        }
        return await testFeed(urlString: stored)
    }

    /// Syncs every feed (conditional GET) and notifies the observer.
    func refreshNow() async {
        guard !isSyncing, !feeds.isEmpty else { return }
        isSyncing = true
        for feed in feeds {
            await sync(feed)
        }
        isSyncing = false
        changeHandler?()
    }

    // MARK: - Private

    private struct CachedFeed {
        let data: ICSCalendarData
        let etag: String?
        let lastModified: String?
    }

    private enum Download {
        case notModified
        case content(ICSCalendarData, etag: String?, lastModified: String?)
    }

    private static func secretKey(for id: String) -> String {
        secretKeyPrefix + id
    }

    private static func feedName(_ name: String, kind: CalendarAccountKind, url: URL) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return kind == .outlook ? defaultOutlookName : (url.host() ?? defaultName)
    }

    private func context(for feed: ICSFeed) -> CalendarSourceContext {
        CalendarSourceContext(
            idPrefix: "ics.\(feed.id)",
            calendarID: feed.calendarID,
            calendarTitle: feed.name,
            color: feed.color,
            account: feed.account
        )
    }

    private func sync(_ feed: ICSFeed) async {
        guard let stored = secrets.secret(for: Self.secretKey(for: feed.id)),
              let url = try? ICSFeedURL.normalized(stored)
        else {
            feedStatus[feed.id] = ICSFeedStatus(errorMessage: FeedError.missingURL.localizedDescription)
            return
        }
        do {
            let previous = cache[feed.id]
            switch try await download(url, conditionalOn: previous) {
            case .notModified:
                var status = feedStatus[feed.id] ?? ICSFeedStatus()
                status.lastSync = now()
                status.errorMessage = nil
                status.eventCount = previous?.data.eventCount
                feedStatus[feed.id] = status
            case let .content(data, etag, lastModified):
                guard feeds.contains(where: { $0.id == feed.id }) else { return }
                cache[feed.id] = CachedFeed(data: data, etag: etag, lastModified: lastModified)
                feedStatus[feed.id] = ICSFeedStatus(lastSync: now(), eventCount: data.eventCount, errorMessage: nil)
            }
        } catch is CancellationError {
            return
        } catch {
            logger.error("ICS feed sync failed: \(error.localizedDescription, privacy: .public)")
            var status = feedStatus[feed.id] ?? ICSFeedStatus()
            status.errorMessage = error.localizedDescription
            feedStatus[feed.id] = status
        }
    }

    private func testResult(for url: URL) async throws -> ICSFeedTestResult {
        switch try await download(url, conditionalOn: nil) {
        case .notModified:
            return .failure(FeedError.http(304).localizedDescription)
        case let .content(data, _, _):
            return .success(eventCount: data.eventCount, calendarName: data.name)
        }
    }

    private func download(_ url: URL, conditionalOn cached: CachedFeed?) async throws -> Download {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.requestTimeout)
        request.setValue("text/calendar, */*;q=0.5", forHTTPHeaderField: "Accept")
        if let etag = cached?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = cached?.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        let (data, response) = try await http.data(for: request)
        if response.statusCode == 304, cached != nil {
            return .notModified
        }
        guard (200..<300).contains(response.statusCode) else { throw FeedError.http(response.statusCode) }
        guard data.count <= Self.maxFeedBytes else { throw FeedError.tooLarge }
        let text = String(decoding: data, as: UTF8.self)
        guard text.range(of: Self.calendarMarker, options: .caseInsensitive) != nil else { throw FeedError.notACalendar }
        let parsed = await Task.detached(priority: .utility) { ICSParser.parse(text) }.value
        return .content(
            parsed,
            etag: response.value(forHTTPHeaderField: "ETag"),
            lastModified: response.value(forHTTPHeaderField: "Last-Modified")
        )
    }
}
