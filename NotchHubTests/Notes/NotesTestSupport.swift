import Foundation
@testable import NotchHub

/// In-memory storage that records every save.
final class InMemoryNotesStorage: NotesStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Note]
    private var saves: [[Note]] = []

    init(_ notes: [Note] = []) {
        stored = notes
    }

    var saveCount: Int { lock.withLock { saves.count } }
    var lastSaved: [Note]? { lock.withLock { saves.last } }

    func load() throws -> [Note] {
        lock.withLock { stored }
    }

    func save(_ notes: [Note]) throws {
        lock.withLock {
            stored = notes
            saves.append(notes)
        }
    }
}

/// Sleeper that suspends until the test calls `resumeAll()`; cancellation throws immediately.
final class ManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private(set) var requestedDurations: [Duration] = []

    var pendingCount: Int { lock.withLock { waiters.count } }

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let alreadyCancelled = lock.withLock { () -> Bool in
                    requestedDurations.append(duration)
                    if Task.isCancelled { return true }
                    waiters[id] = continuation
                    return false
                }
                if alreadyCancelled { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let waiter = lock.withLock { waiters.removeValue(forKey: id) }
            waiter?.resume(throwing: CancellationError())
        }
    }

    func resumeAll() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, any Error>] in
            defer { waiters.removeAll() }
            return Array(waiters.values)
        }
        pending.forEach { $0.resume() }
    }
}

/// Mutable clock for the store under test.
final class NotesTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) {
        current = start
    }

    var now: Date { lock.withLock { current } }

    func advance(by interval: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(interval) }
    }
}

@MainActor
struct NotesFixture {
    let storage: InMemoryNotesStorage
    let sleeper = ManualSleeper()
    let clock = NotesTestClock()
    let exportDirectory = FileManager.default.temporaryDirectory
        .appending(path: "NotesTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init(notes: [Note] = []) {
        storage = InMemoryNotesStorage(notes)
    }

    func makeStore() -> NoteStore {
        let clock = clock
        let sleeper = sleeper
        let store = NoteStore(
            storage: storage,
            now: { clock.now },
            sleep: { try await sleeper.sleep($0) },
            exporter: NoteMarkdownExporter(directory: exportDirectory)
        )
        store.start()
        return store
    }

    /// Lets the pending debounce elapse and waits for the write.
    func flushDebounce(_ store: NoteStore) async {
        let task = store.pendingSave
        while sleeper.pendingCount == 0, task != nil {
            await Task.yield()
        }
        sleeper.resumeAll()
        await task?.value
    }
}
