import AppKit
import Foundation
import Testing
@testable import NotchHub

/// Mutable clock shared with the store under test.
final class ShelfTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(interval) }
    }
}

@MainActor
struct ShelfFixture {
    let suiteName = "NotchHubTests.Shelf.\(UUID().uuidString)"
    let defaults: UserDefaults
    let root: URL
    let storageDirectory: URL
    let clock = ShelfTestClock()

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        root = FileManager.default.temporaryDirectory.appending(path: "ShelfTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        storageDirectory = root.appending(path: "Storage", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeStore() -> ShelfStore {
        let clock = clock
        return ShelfStore(defaults: defaults, now: { clock.now }, storageDirectory: storageDirectory)
    }

    /// A fresh store that has loaded the persisted state (as after `start()`).
    func reloadedStore() -> ShelfStore {
        let store = makeStore()
        store.start()
        store.stop()
        return store
    }

    func makeFile(_ name: String, contents: String = "hello") throws -> URL {
        let url = root.appending(path: name, directoryHint: .notDirectory)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    static func pngData(side: Int = 2) throws -> Data {
        try pngDataNonisolated(side: side)
    }

    nonisolated static func pngDataNonisolated(side: Int = 2) throws -> Data {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    static func tiffData() throws -> Data {
        let image = try #require(NSImage(data: pngData()))
        return try #require(image.tiffRepresentation)
    }
}
