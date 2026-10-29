import AppKit
import Foundation
@testable import NotchHub

/// In-memory pasteboard; every write bumps the change count like `NSPasteboard`.
@MainActor
final class FakeClipboardPasteboard: ClipboardPasteboard {
    private(set) var changeCount = 0
    private(set) var typeIdentifiers: [String] = []
    private var string: String?
    private var image: Data?

    /// Simulates another app copying.
    func simulateCopy(text: String? = nil, image: Data? = nil, extraTypes: [String] = []) {
        string = text
        self.image = image
        var types = extraTypes
        if text != nil { types.append("public.utf8-plain-text") }
        if image != nil { types.append("public.png") }
        typeIdentifiers = types
        changeCount += 1
    }

    func readString() -> String? { string }
    func readImageData() -> Data? { image }

    func write(text: String) -> Int {
        simulateCopy(text: text)
        return changeCount
    }

    func write(png: Data) -> Int {
        simulateCopy(image: png)
        return changeCount
    }
}

@MainActor
struct ClipboardFixture {
    let suiteName: String
    let defaults: UserDefaults
    let root: URL
    let pasteboard = FakeClipboardPasteboard()
    let clock = ShelfTestClock()
    let frontmost = FrontmostBox()

    init() throws {
        let suite = TestDefaults.makeSuite("Clipboard.\(UUID().uuidString)")
        suiteName = suite.name
        defaults = suite.defaults
        root = FileManager.default.temporaryDirectory.appending(path: "ClipboardTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    var storage: ClipboardHistoryStorage {
        ClipboardHistoryStorage(directory: root.appending(path: "Clipboard", directoryHint: .isDirectory))
    }

    func makeStore(policy: ClipboardHistoryPolicy = ClipboardHistoryPolicy()) -> ClipboardHistoryStore {
        let clock = clock
        let frontmost = frontmost
        return ClipboardHistoryStore(
            defaults: defaults,
            storage: storage,
            pasteboard: pasteboard,
            policy: policy,
            now: { clock.now },
            frontmostBundleID: { frontmost.bundleID },
            isIdle: { false },
            sleep: { _, _ in try await Task.sleep(for: .seconds(3600)) }
        )
    }

    /// A started store whose baseline already matches the pasteboard.
    func startedStore(policy: ClipboardHistoryPolicy = ClipboardHistoryPolicy()) -> ClipboardHistoryStore {
        let store = makeStore(policy: policy)
        store.start()
        return store
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
final class FrontmostBox {
    var bundleID: String?
}

enum ClipboardEntryFactory {
    static func text(_ value: String, at seconds: TimeInterval = 0) -> ClipboardEntry {
        ClipboardEntry(
            kind: .text(value),
            capturedAt: Date(timeIntervalSinceReferenceDate: seconds),
            fingerprint: ClipboardImageProcessor.fingerprint(text: value)
        )
    }

    static func image(bytes: Int, tag: String) -> ClipboardEntry {
        ClipboardEntry(
            kind: .image(fileName: "\(tag).png", byteCount: bytes),
            capturedAt: Date(timeIntervalSinceReferenceDate: 0),
            fingerprint: "i:\(tag)"
        )
    }
}
