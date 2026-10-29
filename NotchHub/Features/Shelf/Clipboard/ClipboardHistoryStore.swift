import AppKit
import Observation
import OSLog

/// Records recent clipboard text and images (opt-out, privacy filtered). Contents are never logged.
@MainActor
@Observable
final class ClipboardHistoryStore {
    typealias Sleeper = @Sendable (_ interval: Duration, _ tolerance: Duration) async throws -> Void

    enum Keys {
        static let enabled = "clipboard.historyEnabled"
    }

    private(set) var entries: [ClipboardEntry] = []

    /// "Pano geçmişi" toggle; default on. Turning it off stops polling but keeps existing entries.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Keys.enabled)
            updatePolling()
        }
    }

    var hasEntries: Bool { !entries.isEmpty }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storage: ClipboardHistoryStorage
    @ObservationIgnored private let pasteboard: any ClipboardPasteboard
    @ObservationIgnored private let policy: ClipboardHistoryPolicy
    @ObservationIgnored private let privacy: ClipboardPrivacyFilter
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let frontmostBundleID: @MainActor () -> String?
    @ObservationIgnored private let isIdle: @MainActor () -> Bool
    /// Live lock / sleep tracking; `nil` when tests inject `isIdle`.
    @ObservationIgnored private let activityMonitor: ClipboardActivityMonitor?
    @ObservationIgnored private let sleep: Sleeper
    @ObservationIgnored private var lastChangeCount: Int?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private(set) var pollTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Clipboard")

    init(
        defaults: UserDefaults = .standard,
        storage: ClipboardHistoryStorage = ClipboardHistoryStorage(directory: ClipboardHistoryStorage.defaultDirectory),
        pasteboard: (any ClipboardPasteboard)? = nil,
        policy: ClipboardHistoryPolicy = ClipboardHistoryPolicy(),
        privacy: ClipboardPrivacyFilter = ClipboardPrivacyFilter(),
        now: @escaping @Sendable () -> Date = Date.init,
        frontmostBundleID: @escaping @MainActor () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
        isIdle: (@MainActor () -> Bool)? = nil,
        sleep: @escaping Sleeper = { interval, tolerance in try await Task.sleep(for: interval, tolerance: tolerance) }
    ) {
        self.defaults = defaults
        self.storage = storage
        self.pasteboard = pasteboard ?? SystemClipboardPasteboard()
        self.policy = policy
        self.privacy = privacy
        self.now = now
        self.frontmostBundleID = frontmostBundleID
        if let isIdle {
            self.isIdle = isIdle
            activityMonitor = nil
        } else {
            let monitor = ClipboardActivityMonitor()
            self.isIdle = { monitor.isIdle }
            activityMonitor = monitor
        }
        self.sleep = sleep
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
    }

    // MARK: - Lifecycle

    /// Loads the history and starts polling when enabled. Whatever is already on the clipboard is not recorded.
    func start() {
        ensureLoaded()
        isStarted = true
        updatePolling()
    }

    func stop() {
        isStarted = false
        updatePolling()
    }

    /// Checks the pasteboard once; the poll loop calls this, tests call it directly.
    func poll() {
        guard isEnabled else { return }
        let count = pasteboard.changeCount
        guard let last = lastChangeCount else {
            lastChangeCount = count
            return
        }
        guard count != last else { return }
        lastChangeCount = count
        capture()
    }

    // MARK: - Actions

    /// Puts the entry back on the clipboard without recording it again.
    func copy(_ id: ClipboardEntry.ID) {
        guard let entry = entry(with: id) else { return }
        switch entry.kind {
        case .text(let text):
            lastChangeCount = pasteboard.write(text: text)
        case .image(let fileName, _):
            guard let data = storage.readImage(fileName: fileName) else {
                logger.error("Clipboard image file is missing")
                return remove(id)
            }
            lastChangeCount = pasteboard.write(png: data)
        }
    }

    /// Adds the entry to the shelf proper, where it follows the shelf retention.
    func pin(_ id: ClipboardEntry.ID, to shelf: ShelfStore) {
        guard let entry = entry(with: id) else { return }
        switch entry.kind {
        case .text(let text):
            shelf.add(text: text)
        case .image(let fileName, _):
            guard let data = storage.readImage(fileName: fileName) else {
                logger.error("Clipboard image file is missing")
                return
            }
            shelf.add(imageData: data)
        }
    }

    func remove(_ id: ClipboardEntry.ID) {
        guard let entry = entry(with: id) else { return }
        entries = entries.filter { $0.id != id }
        discardFiles(of: [entry])
        persist()
    }

    /// "Geçmişi temizle": drops every entry and the storage folder.
    func clear() {
        entries = []
        do {
            try storage.removeAll()
        } catch {
            logger.error("Cannot clear clipboard history: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Queries

    func entry(with id: ClipboardEntry.ID) -> ClipboardEntry? {
        entries.first { $0.id == id }
    }

    func imageURL(for entry: ClipboardEntry) -> URL? {
        entry.imageFileName.map(storage.imageURL(for:))
    }

    func imageData(for entry: ClipboardEntry) -> Data? {
        entry.imageFileName.flatMap(storage.readImage(fileName:))
    }

    // MARK: - Capture

    private func capture() {
        let types = pasteboard.typeIdentifiers
        guard privacy.allowsCapture(types: types, frontmostBundleID: frontmostBundleID()) else {
            logger.debug("Skipped a sensitive clipboard change")
            return
        }
        let entry: ClipboardEntry? = switch ClipboardCaptureKind.preferred(for: types) {
        case .text: makeTextEntry()
        case .image: makeImageEntry()
        case .none: nil
        }
        guard let entry else { return }
        insert(entry)
    }

    private func makeTextEntry() -> ClipboardEntry? {
        guard let raw = pasteboard.readString(), let text = policy.normalizedText(raw) else { return nil }
        return ClipboardEntry(kind: .text(text), capturedAt: now(), fingerprint: ClipboardImageProcessor.fingerprint(text: text))
    }

    private func makeImageEntry() -> ClipboardEntry? {
        guard let raw = pasteboard.readImageData(), let png = ClipboardImageProcessor.downscaledPNG(from: raw) else {
            logger.notice("Clipboard image could not be decoded")
            return nil
        }
        guard policy.acceptsImage(byteCount: png.count) else {
            logger.notice("Clipboard image exceeds the size budget")
            return nil
        }
        let fingerprint = ClipboardImageProcessor.fingerprint(imageData: png)
        if let existing = entries.first(where: { $0.fingerprint == fingerprint }) {
            return ClipboardEntry(kind: existing.kind, capturedAt: now(), fingerprint: fingerprint)
        }
        let fileName = "\(UUID().uuidString).png"
        do {
            try storage.writeImage(png, fileName: fileName)
        } catch {
            logger.error("Cannot store clipboard image: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return ClipboardEntry(kind: .image(fileName: fileName, byteCount: png.count), capturedAt: now(), fingerprint: fingerprint)
    }

    private func insert(_ entry: ClipboardEntry) {
        let insertion = policy.inserting(entry, into: entries)
        entries = insertion.entries
        discardFiles(of: insertion.evicted)
        persist()
        logger.debug("Clipboard history now has \(insertion.entries.count) entries")
    }

    /// Deletes image files no longer referenced by a kept entry (a re-copied image keeps its file).
    private func discardFiles(of removed: [ClipboardEntry]) {
        let inUse = Set(entries.compactMap(\.imageFileName))
        for name in removed.compactMap(\.imageFileName) where !inUse.contains(name) {
            storage.deleteImage(fileName: name)
        }
    }

    // MARK: - Polling

    private func updatePolling() {
        let shouldPoll = isStarted && isEnabled
        if shouldPoll, pollTask == nil {
            lastChangeCount = pasteboard.changeCount
            activityMonitor?.start()
            pollTask = Task { [weak self] in await self?.runPollLoop() }
        } else if !shouldPoll, let task = pollTask {
            task.cancel()
            pollTask = nil
            activityMonitor?.stop()
        }
    }

    private func runPollLoop() async {
        while !Task.isCancelled {
            let pace = ClipboardPollSchedule.interval(isIdle: isIdle())
            do {
                try await sleep(pace.interval, pace.tolerance)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            poll()
        }
    }

    // MARK: - Persistence

    private func ensureLoaded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        let stored: [ClipboardEntry]
        do {
            stored = try storage.loadIndex() ?? []
        } catch {
            logger.error("Discarding unreadable clipboard history: \(error.localizedDescription, privacy: .public)")
            clear()
            return
        }
        let present = stored.filter { entry in
            guard let name = entry.imageFileName else { return true }
            return FileManager.default.fileExists(atPath: storage.imageURL(for: name).path(percentEncoded: false))
        }
        entries = policy.trim(present).kept
        storage.removeOrphans(keeping: Set(entries.compactMap(\.imageFileName)))
        if entries.count != stored.count { persist() }
    }

    private func persist() {
        do {
            try storage.saveIndex(entries)
        } catch {
            logger.error("Cannot persist clipboard history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
