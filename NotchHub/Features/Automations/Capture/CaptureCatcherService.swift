import Foundation
import Observation
import OSLog

/// Watches the screenshot folder(s) and ~/Downloads and offers new files for the shelf.
@MainActor
@Observable
final class CaptureCatcherService {
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    static let alertKey = "captureCatcher.batch"
    static let alertDuration: Duration = .seconds(8)
    nonisolated static let pollInterval: Duration = .milliseconds(500)
    /// A file that stays pending without file events (e.g. a stalled download) is re-checked at most this slowly.
    nonisolated static let maxIdlePollInterval: Duration = .seconds(5)
    /// Quiet pumps at `pollInterval` before backing off; covers the 1 s stability and 1.5 s burst windows.
    nonisolated static let idlePumpGrace = 8

    private enum Keys {
        static let isEnabled = "CaptureCatcher.isEnabled"
        static let watchScreenshots = "CaptureCatcher.watchScreenshots"
        static let watchDownloads = "CaptureCatcher.watchDownloads"
        static let autoAddScreenshots = "CaptureCatcher.autoAddScreenshots"
        static let includeSubfolders = "CaptureCatcher.includeSubfolders"
        static let customFolder = "CaptureCatcher.customScreenshotFolder"
    }

    var isEnabled: Bool {
        didSet { persist(isEnabled, Keys.isEnabled) }
    }

    var watchScreenshots: Bool {
        didSet { persist(watchScreenshots, Keys.watchScreenshots) }
    }

    var watchDownloads: Bool {
        didSet { persist(watchDownloads, Keys.watchDownloads) }
    }

    var autoAddScreenshots: Bool {
        didSet { defaults.set(autoAddScreenshots, forKey: Keys.autoAddScreenshots) }
    }

    var includeSubfolders: Bool {
        didSet { persist(includeSubfolders, Keys.includeSubfolders) }
    }

    /// Extra screenshot folder picked by the user (e.g. when another tool saves elsewhere).
    var customScreenshotFolder: String? {
        didSet { persist(customScreenshotFolder, Keys.customFolder) }
    }

    private(set) var isRunning = false
    /// `false` when the FSEvents stream could not be started.
    private(set) var isWatching = false
    private(set) var watchedFolders: [String] = []
    private(set) var lastBatch: CaptureBatch?
    /// URLs from `lastBatch` already on the shelf.
    private(set) var shelvedURLs: Set<URL> = []

    @ObservationIgnored private var classifier = CaptureClassifier(config: CaptureWatchConfig(
        screenshotFolders: [],
        downloadFolders: []
    ))
    @ObservationIgnored private var aggregator = CaptureBurstAggregator()
    @ObservationIgnored private var pumpTask: Task<Void, Never>?
    /// Pumps in a row that found nothing new while files are still pending; drives the back-off.
    @ObservationIgnored private var idlePumps = 0
    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let addToShelf: @MainActor ([URL]) -> Void
    @ObservationIgnored private let watcher: any CaptureFileWatching
    @ObservationIgnored private let probe: any CaptureFileProbing
    @ObservationIgnored private let folders: CaptureFolderResolver
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let sleep: Sleeper
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "CaptureCatcher")

    init(
        alerts: NotchAlertCenter,
        addToShelf: @escaping @MainActor ([URL]) -> Void,
        watcher: any CaptureFileWatching,
        probe: any CaptureFileProbing = SystemCaptureFileProbe(),
        folders: CaptureFolderResolver = CaptureFolderResolver(),
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.alerts = alerts
        self.addToShelf = addToShelf
        self.watcher = watcher
        self.probe = probe
        self.folders = folders
        self.defaults = defaults
        self.now = now
        self.sleep = sleep
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        watchScreenshots = defaults.object(forKey: Keys.watchScreenshots) as? Bool ?? true
        watchDownloads = defaults.object(forKey: Keys.watchDownloads) as? Bool ?? true
        autoAddScreenshots = defaults.object(forKey: Keys.autoAddScreenshots) as? Bool ?? false
        includeSubfolders = defaults.object(forKey: Keys.includeSubfolders) as? Bool ?? false
        customScreenshotFolder = defaults.string(forKey: Keys.customFolder)
    }

    // MARK: - Derived state

    var currentConfig: CaptureWatchConfig {
        folders.config(
            watchScreenshots: watchScreenshots,
            watchDownloads: watchDownloads,
            customFolder: customScreenshotFolder,
            includeSubfolders: includeSubfolders
        )
    }

    /// Folders needing "Files and Folders" (TCC) consent; the system asks lazily on first access in `start()`.
    var protectedFolders: [String] { folders.protectedFolders(in: currentConfig) }

    var detectedShottrFolder: String? { folders.shottrFolder }
    var systemScreenshotFolder: String { folders.systemScreenshotFolder }

    var canShelveLastBatch: Bool {
        guard let lastBatch else { return false }
        return lastBatch.urls.contains { !shelvedURLs.contains($0) }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        restartWatching()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        restartWatching()
    }

    // MARK: - Actions

    func shelve(_ urls: [URL]) {
        let fresh = urls.filter { !shelvedURLs.contains($0) }
        guard !fresh.isEmpty else { return }
        addToShelf(fresh)
        shelvedURLs.formUnion(fresh)
    }

    func shelveLastBatch() {
        guard let lastBatch else { return }
        shelve(lastBatch.urls)
    }

    // MARK: - Events (exposed for tests)

    func handle(_ events: [CaptureFileEvent]) {
        classifier.ingest(events, now: now(), probe: probe)
        if Self.pumpDelay(idlePumps: idlePumps) > Self.pollInterval {
            // A backed-off pump would sleep through the new events; restart it at full pace.
            pumpTask?.cancel()
            pumpTask = nil
        }
        idlePumps = 0
        startPumpIfNeeded()
    }

    /// One poll/flush step; the pump task calls it every `pollInterval` while work is outstanding.
    func pump() {
        let date = now()
        let detections = classifier.poll(now: date, probe: probe)
        idlePumps = detections.isEmpty && aggregator.isEmpty ? idlePumps + 1 : 0
        aggregator.add(detections, now: date)
        if let batch = aggregator.flush(now: date) {
            deliver(batch)
        }
    }

    var hasOutstandingWork: Bool { classifier.hasPending || !aggregator.isEmpty }

    // MARK: - Private

    private func deliver(_ batch: CaptureBatch) {
        logger.info("Captured \(batch.detections.count) file(s)")
        lastBatch = batch
        shelvedURLs = []
        if autoAddScreenshots {
            shelve(batch.screenshots.map(\.url))
        }
        let remaining = batch.urls.filter { !shelvedURLs.contains($0) }
        let isAllShelved = remaining.isEmpty
        var action: (@MainActor () -> Void)?
        if !isAllShelved {
            action = { [weak self] in self?.shelve(remaining) }
        }
        alerts.post(NotchAlert(
            module: .shelf,
            systemImage: batch.systemImage,
            title: isAllShelved ? "\(batch.title) · Rafta" : batch.title,
            subtitle: batch.subtitle,
            style: isAllShelved ? .success : .info,
            coalescingKey: Self.alertKey,
            autoDismissAfter: Self.alertDuration,
            actionTitle: isAllShelved ? nil : "Rafa ekle",
            action: action
        ))
    }

    private func persist(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: key)
        restartWatching()
    }

    private func restartWatching() {
        watcher.stop()
        pumpTask?.cancel()
        pumpTask = nil
        aggregator = CaptureBurstAggregator()
        guard isRunning, isEnabled else {
            isWatching = false
            watchedFolders = []
            return
        }
        let config = currentConfig
        classifier.config = config
        watchedFolders = config.allFolders
        isWatching = watcher.start(paths: config.allFolders) { [weak self] events in
            self?.handle(events)
        }
        if !isWatching, !config.allFolders.isEmpty {
            logger.error("Could not watch capture folders")
        }
    }

    private func startPumpIfNeeded() {
        guard pumpTask == nil, hasOutstandingWork else { return }
        let sleep = sleep
        pumpTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self.map({ Self.pumpDelay(idlePumps: $0.idlePumps) }) else { return }
                do {
                    try await sleep(delay)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                self.pump()
                if !self.hasOutstandingWork {
                    self.pumpTask = nil
                    self.idlePumps = 0
                    return
                }
            }
        }
    }

    nonisolated static func pumpDelay(idlePumps: Int) -> Duration {
        PowerAwareScheduler.backoff(
            base: pollInterval, maximum: maxIdlePollInterval, unchangedCount: idlePumps, graceCount: idlePumpGrace
        )
    }
}
