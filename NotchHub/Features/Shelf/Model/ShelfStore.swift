import AppKit
import Observation
import OSLog

/// Owns the shelf items, their persistence and automatic clean-up.
@MainActor
@Observable
final class ShelfStore {
    static let purgeInterval: Duration = .seconds(60)

    private enum Keys {
        static let items = "shelf.items"
        static let retention = "shelf.retention"
    }

    private(set) var items: [ShelfItem] = []

    var retention: ShelfRetention {
        didSet {
            defaults.set(retention.rawValue, forKey: Keys.retention)
            purgeExpired()
        }
    }

    var hasItems: Bool { !items.isEmpty }
    var count: Int { items.count }

    /// Set while the user drags items out of the shelf, so they are not dropped back onto it.
    @ObservationIgnored var isDraggingOut = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let storage: ShelfPayloadStorage
    @ObservationIgnored private let bookmarker: any ShelfBookmarking
    @ObservationIgnored private var bookmarks: [ShelfItem.ID: Data] = [:]
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var purgeTask: Task<Void, Never>?
    @ObservationIgnored let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Shelf")

    init(
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init,
        storageDirectory: URL = ShelfPayloadStorage.defaultDirectory,
        bookmarker: any ShelfBookmarking = FileBookmarker()
    ) {
        self.defaults = defaults
        self.now = now
        self.storage = ShelfPayloadStorage(directory: storageDirectory)
        self.bookmarker = bookmarker
        retention = defaults.string(forKey: Keys.retention).flatMap(ShelfRetention.init) ?? .oneDay
    }

    // MARK: - Lifecycle

    /// Loads persisted items, purges expired ones and keeps purging periodically.
    func start() {
        ensureLoaded()
        purgeExpired()
        guard purgeTask == nil else { return }
        purgeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await PowerAwareScheduler.sleep(for: Self.purgeInterval)
                guard !Task.isCancelled, let self else { return }
                self.purgeExpired()
            }
        }
    }

    func stop() {
        purgeTask?.cancel()
        purgeTask = nil
    }

    // MARK: - Adding

    func add(fileURLs: [URL]) {
        ensureLoaded()
        var knownKeys = Set(items.compactMap(\.fileURL).map(Self.identityKey))
        var added: [ShelfItem] = []
        for url in fileURLs where url.isFileURL {
            let fileURL = url.standardizedFileURL
            guard knownKeys.insert(Self.identityKey(fileURL)).inserted else { continue }
            do {
                let bookmark = try bookmarker.bookmarkData(for: fileURL)
                let item = ShelfItem(kind: .file(fileURL), addedAt: now())
                bookmarks[item.id] = bookmark
                added.append(item)
            } catch {
                logger.error("Cannot bookmark \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        insert(added)
    }

    func add(text: String) {
        ensureLoaded()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let item = ShelfItem(kind: .text(text), addedAt: now())
        writePayload(Data(text.utf8), for: item.id, type: .text)
        insert([item])
    }

    func add(imageData: Data) {
        ensureLoaded()
        guard let png = ShelfImageEncoding.pngData(from: imageData) else {
            logger.error("Ignoring image data that cannot be decoded")
            return
        }
        let item = ShelfItem(kind: .image(png), addedAt: now())
        writePayload(png, for: item.id, type: .image)
        insert([item])
    }

    /// Adds whatever the pasteboard holds, preferring files, then images, then text.
    @discardableResult
    func pasteFromClipboard(_ pasteboard: NSPasteboard = .general) -> Bool {
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL], !urls.isEmpty {
            add(fileURLs: urls)
            return true
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            add(imageData: data)
            return true
        }
        if let string = pasteboard.string(forType: .string) {
            add(text: string)
            return true
        }
        return false
    }

    // MARK: - Removing

    func remove(_ id: ShelfItem.ID) {
        remove(ids: [id])
    }

    func remove(ids: Set<ShelfItem.ID>) {
        ensureLoaded()
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        items = items.filter { !ids.contains($0.id) }
        removed.forEach(discardResources)
        persistIndex()
    }

    func removeAll() {
        remove(ids: Set(items.map(\.id)))
    }

    func purgeExpired() {
        guard let interval = retention.interval else { return }
        ensureLoaded()
        let cutoff = now().addingTimeInterval(-interval)
        let expired = items.filter { $0.addedAt <= cutoff }.map(\.id)
        guard !expired.isEmpty else { return }
        logger.info("Purging \(expired.count) expired shelf items")
        remove(ids: Set(expired))
    }

    // MARK: - Queries

    func item(with id: ShelfItem.ID) -> ShelfItem? {
        items.first { $0.id == id }
    }

    func items(with ids: [ShelfItem.ID]) -> [ShelfItem] {
        ids.compactMap(item(with:))
    }

    /// A file URL suitable for Quick Look / AirDrop: the file itself or the stored payload.
    func previewURL(for item: ShelfItem) -> URL? {
        let url: URL = switch item.kind {
        case .file(let fileURL): fileURL
        case .text: storage.url(for: item.id, type: .text)
        case .image: storage.url(for: item.id, type: .image)
        }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    // MARK: - Private

    private func insert(_ newItems: [ShelfItem]) {
        guard !newItems.isEmpty else { return }
        items = newItems + items
        persistIndex()
    }

    private func writePayload(_ data: Data, for id: UUID, type: ShelfPayloadStorage.PayloadType) {
        do {
            try storage.write(data, for: id, type: type)
        } catch {
            logger.error("Cannot store shelf payload: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func discardResources(of item: ShelfItem) {
        bookmarks[item.id] = nil
        switch item.kind {
        case .file: break
        case .text: storage.delete(item.id, type: .text)
        case .image: storage.delete(item.id, type: .image)
        }
    }

    private static func identityKey(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
    }

    // MARK: - Persistence

    private func ensureLoaded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        items = loadPersistedItems()
        storage.removeOrphans(keeping: Set(items.filter { !$0.isFile }.map(\.id)))
    }

    private func loadPersistedItems() -> [ShelfItem] {
        guard let data = defaults.data(forKey: Keys.items) else { return [] }
        guard let records = ShelfRecord.decodeList(from: data) else {
            logger.error("Discarding unreadable shelf index")
            defaults.removeObject(forKey: Keys.items)
            return []
        }
        var needsRewrite = false
        let restored = records.compactMap { record in
            let item = restore(record, needsRewrite: &needsRewrite)
            if item == nil { needsRewrite = true }
            return item
        }
        if needsRewrite {
            items = restored
            persistIndex()
        }
        return restored
    }

    private func restore(_ record: ShelfRecord, needsRewrite: inout Bool) -> ShelfItem? {
        switch record.knownKind {
        case .file:
            guard let bookmark = record.bookmark, let resolved = bookmarker.resolve(bookmark) else { return nil }
            var storedBookmark = bookmark
            if resolved.isStale, let fresh = try? bookmarker.bookmarkData(for: resolved.url) {
                storedBookmark = fresh
                needsRewrite = true
            }
            bookmarks[record.id] = storedBookmark
            return ShelfItem(id: record.id, kind: .file(resolved.url), addedAt: record.addedAt)
        case .text:
            guard let data = storage.read(record.id, type: .text), let text = String(data: data, encoding: .utf8) else {
                return nil
            }
            return ShelfItem(id: record.id, kind: .text(text), addedAt: record.addedAt)
        case .image:
            guard let data = storage.read(record.id, type: .image) else { return nil }
            return ShelfItem(id: record.id, kind: .image(data), addedAt: record.addedAt)
        case nil:
            return nil
        }
    }

    private func persistIndex() {
        let records = items.compactMap(record(for:))
        do {
            defaults.set(try JSONEncoder().encode(records), forKey: Keys.items)
        } catch {
            logger.error("Cannot persist shelf index: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func record(for item: ShelfItem) -> ShelfRecord? {
        switch item.kind {
        case .file:
            guard let bookmark = bookmarks[item.id] else { return nil }
            return ShelfRecord(id: item.id, kind: .file, addedAt: item.addedAt, bookmark: bookmark)
        case .text:
            return ShelfRecord(id: item.id, kind: .text, addedAt: item.addedAt)
        case .image:
            return ShelfRecord(id: item.id, kind: .image, addedAt: item.addedAt)
        }
    }
}
