import AppKit
import Foundation
import Testing
@testable import NotchHub

@MainActor
struct ClipboardHistoryStoreTests {
    @Test func ignoresWhatWasOnTheClipboardAtStart() throws {
        let fixture = try ClipboardFixture()
        defer { fixture.cleanUp() }
        fixture.pasteboard.simulateCopy(text: "before launch")
        let store = fixture.startedStore()

        store.poll()

        #expect(store.entries.isEmpty)
        store.stop()
    }

    @Test func capturesTrimmedTextNewestFirst() throws {
        let fixture = try ClipboardFixture()
        defer { fixture.cleanUp() }
        let store = fixture.startedStore()

        fixture.pasteboard.simulateCopy(text: "  first \n")
        store.poll()
        fixture.pasteboard.simulateCopy(text: "second")
        store.poll()
        store.poll()

        #expect(store.entries.compactMap(\.text) == ["second", "first"])
        store.stop()
    }

    @Test func dedupesRepeatedCopies() throws {
        let fixture = try ClipboardFixture()
        defer { fixture.cleanUp() }
        let store = fixture.startedStore()

        for text in ["a", "b", "a"] {
            fixture.pasteboard.simulateCopy(text: text)
            store.poll()
        }

        #expect(store.entries.compactMap(\.text) == ["a", "b"])
        store.stop()
    }

    @Test func skipsConcealedAndPasswordManagerCopies() throws {
        let fixture = try ClipboardFixture()
        defer { fixture.cleanUp() }
        let store = fixture.startedStore()

        fixture.pasteboard.simulateCopy(text: "secret", extraTypes: ["org.nspasteboard.ConcealedType"])
        store.poll()
        fixture.frontmost.bundleID = "com.bitwarden.desktop"
        fixture.pasteboard.simulateCopy(text: "hunter2")
        store.poll()
        fixture.frontmost.bundleID = "com.apple.TextEdit"
        fixture.pasteboard.simulateCopy(text: "visible")
        store.poll()

        #expect(store.entries.compactMap(\.text) == ["visible"])
        store.stop()
    }

    @Test func copyingBackIsNotRecapturedAndKeepsOrder() throws {
        let fixture = try ClipboardFixture()
        defer { fixture.cleanUp() }
        let store = fixture.startedStore()
        for text in ["old", "new"] {
            fixture.pasteboard.simulateCopy(text: text)
            store.poll()
        }
        let old = try #require(store.entries.last)

        store.copy(old.id)
        store.poll()

        #expect(fixture.pasteboard.readString() == "old")
        #expect(store.entries.compactMap(\.text) == ["new", "old"])
        #expect(store.entries.last?.id == old.id)
        store.stop()
    }

    @Test func disabledHistoryDoesNotCaptureAndPersistsSetting() throws {
        let fixture = try ClipboardFixture()
        defer { fixture.cleanUp() }
        let store = fixture.startedStore()
        #expect(store.isEnabled)
        #expect(store.pollTask != nil)

        store.isEnabled = false
        fixture.pasteboard.simulateCopy(text: "ignored")
        store.poll()

        #expect(store.entries.isEmpty)
        #expect(store.pollTask == nil)
        #expect(fixture.makeStore().isEnabled == false)
        store.stop()
    }

    @Test func capturesImagesAsFilesAndClearRemovesThem() throws {
        let fixture = try ClipboardFixture()
        defer { fixture.cleanUp() }
        let store = fixture.startedStore()

        fixture.pasteboard.simulateCopy(image: try ShelfFixture.pngData(side: 4))
        store.poll()
        let entry = try #require(store.entries.first)
        let url = try #require(store.imageURL(for: entry))

        #expect(entry.isImage)
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(store.imageData(for: entry) != nil)

        store.clear()

        #expect(store.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        store.stop()
    }

    @Test func sameImageTwiceKeepsOneFile() throws {
        let fixture = try ClipboardFixture()
        defer { fixture.cleanUp() }
        let store = fixture.startedStore()
        let png = try ShelfFixture.pngData(side: 4)

        fixture.pasteboard.simulateCopy(image: png)
        store.poll()
        fixture.pasteboard.simulateCopy(image: png)
        store.poll()

        let entry = try #require(store.entries.first)
        let url = try #require(store.imageURL(for: entry))
        #expect(store.entries.count == 1)
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        store.stop()
    }

    @Test func persistsAcrossLaunches() throws {
        let fixture = try ClipboardFixture()
        defer { fixture.cleanUp() }
        let store = fixture.startedStore()
        fixture.pasteboard.simulateCopy(text: "kept")
        store.poll()
        store.stop()

        let reloaded = fixture.startedStore()

        #expect(reloaded.entries.compactMap(\.text) == ["kept"])
        reloaded.stop()
    }

    @Test func pinAddsEntryToShelfAndRemoveDeletes() throws {
        let fixture = try ClipboardFixture()
        defer { fixture.cleanUp() }
        let shelfFixture = try ShelfFixture()
        defer { shelfFixture.cleanUp() }
        let shelf = shelfFixture.makeStore()
        let store = fixture.startedStore()
        fixture.pasteboard.simulateCopy(text: "pin me")
        store.poll()
        let entry = try #require(store.entries.first)

        store.pin(entry.id, to: shelf)
        store.remove(entry.id)

        #expect(shelf.items.compactMap(\.text) == ["pin me"])
        #expect(store.entries.isEmpty)
        store.stop()
    }
}
