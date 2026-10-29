import AppKit
import Foundation
import OSLog

/// Sandbox for screenshot rendering: throwaway defaults and a temporary folder, removed by `cleanUp()`.
/// Every demo service reads and writes only here, never the user's real stores.
@MainActor
final class DemoEnvironment {
    let defaults: UserDefaults
    let directory: URL
    private let suiteName: String
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Screenshots")

    init() throws {
        let token = UUID().uuidString
        suiteName = "\(AppIdentity.bundleID).screenshots.\(token)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw DemoError.defaultsUnavailable }
        self.defaults = defaults
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("NotchHubScreenshots-\(token)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func subdirectory(_ name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: true)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            logger.error("Could not remove the screenshot sandbox: \(error.localizedDescription, privacy: .public)")
        }
    }

    enum DemoError: Error {
        case defaultsUnavailable
    }
}

extension ModuleCoreServices {
    /// Services fed only by `DemoFixtures`; none of them is started, so no monitor, player or store is read.
    static func demo(in environment: DemoEnvironment, now: Date) -> ModuleCoreServices {
        let defaults = environment.defaults
        let fixedNow: @Sendable () -> Date = { now }
        return ModuleCoreServices(
            defaults: defaults,
            shelf: ShelfStore(defaults: defaults, now: fixedNow, storageDirectory: environment.subdirectory("Shelf")),
            clipboard: ClipboardHistoryStore(
                defaults: defaults,
                storage: ClipboardHistoryStorage(directory: environment.subdirectory("Clipboard")),
                pasteboard: DemoClipboardPasteboard(),
                isIdle: { true }
            ),
            media: MediaService(providers: [DemoMediaProvider(artwork: DemoArtwork.pngData())], events: nil),
            audio: AudioOutputService(),
            timer: TimerService(
                defaults: defaults,
                clock: DemoTimerClock(headStart: DemoFixtures.timerElapsed),
                notifier: DemoTimerNotifier()
            ),
            calendar: CalendarService(sources: [DemoCalendarSource(now: now)], defaults: defaults, now: fixedNow),
            notes: NoteStore(storage: DemoNotesStorage(now: now), now: fixedNow),
            calculator: QuickCalcService(defaults: defaults, copy: { _ in }),
            weather: WeatherService(
                defaults: defaults,
                fetcher: DemoWeatherFetcher(),
                locator: DemoWeatherLocator(),
                cache: DemoWeatherCache(snapshot: DemoWeather.snapshot(at: now))
            )
        )
    }
}

// MARK: - Fakes

struct DemoMediaProvider: MediaProvider {
    let artwork: Data?
    var source: MediaSource { .spotify }

    func isRunning() async -> Bool { true }

    func fetchNowPlaying() async throws -> NowPlaying? {
        let track = DemoFixtures.track
        return NowPlaying(
            title: track.title, artist: track.artist, album: track.album,
            duration: track.duration, position: track.position, isPlaying: true,
            source: source, artworkID: track.artworkID
        )
    }

    func playPause() async throws {}
    func next() async throws {}
    func previous() async throws {}
    func seek(to position: TimeInterval) async throws {}
    func fetchArtwork(for track: NowPlaying) async throws -> Data? { artwork }
}

final class DemoCalendarSource: CalendarEventSource {
    private let now: Date
    private let account = CalendarAccount(id: DemoFixtures.accountID, title: "", kind: .iCloud)

    init(now: Date) {
        self.now = now
    }

    var authorization: CalendarAuthorization { .authorized }
    func requestAccess() async -> CalendarAuthorization { .authorized }
    func accounts() -> [CalendarAccount] { [account] }

    func calendars() -> [CalendarInfo] {
        [CalendarInfo(id: DemoFixtures.calendarID, title: DemoFixtures.calendarTitle, color: .fallback, accountID: account.id)]
    }

    func events(from start: Date, to end: Date) throws -> [CalendarEvent] {
        DemoFixtures.events.map(event(for:)).filter { $0.end > start && $0.start < end }
    }

    func startObservingChanges(_ handler: @escaping @MainActor () -> Void) {}
    func stopObservingChanges() {}

    private func event(for spec: DemoFixtures.EventSpec) -> CalendarEvent {
        let start = now.addingTimeInterval(TimeInterval(spec.startOffsetMinutes * 60))
        let link = zip(spec.provider, DemoFixtures.meetingURL).map { MeetingLink(provider: $0, url: $1) }
        return CalendarEvent(
            id: spec.id, title: spec.title, start: start,
            end: start.addingTimeInterval(TimeInterval(spec.durationMinutes * 60)),
            calendarColor: spec.color, location: spec.location, meetingLink: link,
            calendarID: DemoFixtures.calendarID, calendarTitle: DemoFixtures.calendarTitle, account: account
        )
    }
}

private func zip<A, B>(_ first: A?, _ second: B?) -> (A, B)? {
    guard let first, let second else { return nil }
    return (first, second)
}

struct DemoNotesStorage: NotesStorage {
    let now: Date

    func load() throws -> [Note] {
        DemoFixtures.notes.map { spec in
            let date = now.addingTimeInterval(-TimeInterval(spec.ageMinutes * 60))
            return Note(
                body: spec.body, createdAt: date, meetingTitle: spec.meetingTitle,
                clientName: spec.clientName, isPinned: spec.isPinned
            )
        }
    }

    /// Demo notes are never persisted.
    func save(_ notes: [Note]) throws {}
}

enum DemoWeather {
    static func snapshot(at now: Date) -> WeatherSnapshot {
        let spec = DemoFixtures.weather
        let hourly = spec.hourlyTemperatures.enumerated().map { index, temperature in
            WeatherHour(
                time: now.addingTimeInterval(TimeInterval(index * 3600)),
                temperature: temperature, condition: index < 4 ? spec.condition : .mainlyClear, isDay: index < 5
            )
        }
        return WeatherSnapshot(
            fetchedAt: now, coordinate: WeatherCoordinate(latitude: 0, longitude: 0), placeName: nil,
            temperature: spec.temperature, condition: spec.condition, isDay: true,
            high: spec.high, low: spec.low, hourly: hourly
        )
    }
}

final class DemoWeatherCache: WeatherCaching {
    private var snapshot: WeatherSnapshot?

    init(snapshot: WeatherSnapshot) {
        self.snapshot = snapshot
    }

    func load() -> WeatherSnapshot? { snapshot }
    func save(_ snapshot: WeatherSnapshot) { self.snapshot = snapshot }
    func clear() { snapshot = nil }
}

/// Never asks for the location; the demo forecast comes from the cache.
final class DemoWeatherLocator: WeatherLocating {
    var isDenied: Bool { false }
    func currentCoordinate() async throws -> WeatherCoordinate { WeatherCoordinate(latitude: 0, longitude: 0) }
    func cityName(for coordinate: WeatherCoordinate) async -> String? { nil }
}

/// Fails every request, so the demo never reaches the network.
struct DemoWeatherFetcher: WeatherHTTPFetching {
    struct Offline: Error {}
    func data(from url: URL) async throws -> Data { throw Offline() }
}

/// Never requests notification authorization or posts a notification.
final class DemoTimerNotifier: TimerNotifier {
    func prepare() {}
    func timerDidFinish(_ completion: TimerCompletion) {}
}

/// An empty pasteboard, so the clipboard history never sees the user's clipboard.
final class DemoClipboardPasteboard: ClipboardPasteboard {
    var changeCount: Int { 0 }
    var typeIdentifiers: [String] { [] }
    func readString() -> String? { nil }
    func readImageData() -> Data? { nil }
    func write(text: String) -> Int { 0 }
    func write(png: Data) -> Int { 0 }
}

/// Wall-clock time, except that the first reading (the timer's start) lies `headStart` in the past,
/// so the demo countdown shows a session in progress.
final class DemoTimerClock: TimerClock, @unchecked Sendable {
    private let lock = NSLock()
    private var pendingHeadStart: TimeInterval

    init(headStart: TimeInterval) {
        pendingHeadStart = headStart
    }

    var now: Date {
        let shift = lock.withLock {
            let shift = pendingHeadStart
            pendingHeadStart = 0
            return shift
        }
        return Date().addingTimeInterval(-shift)
    }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
