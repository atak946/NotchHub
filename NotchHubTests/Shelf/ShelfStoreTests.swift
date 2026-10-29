import AppKit
import Foundation
import Testing
@testable import NotchHub

@MainActor
struct ShelfStoreTests {
    @Test func addsFilesNewestFirstAndDedupesSameFile() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()
        let first = try fixture.makeFile("a.txt")
        let second = try fixture.makeFile("b.txt")

        store.add(fileURLs: [first, first])
        store.add(fileURLs: [second, URL(filePath: first.path(percentEncoded: false) + "/../a.txt")])

        #expect(store.items.map(\.displayName) == ["b.txt", "a.txt"])
        #expect(store.count == 2)
        #expect(store.hasItems)
    }

    @Test func ignoresMissingAndNonFileURLs() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()

        store.add(fileURLs: [fixture.root.appending(path: "missing.txt"), try #require(URL(string: "https://example.com"))])

        #expect(store.items.isEmpty)
    }

    @Test func addsTextAndIgnoresBlankText() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()

        store.add(text: "  \n ")
        store.add(text: "Hello shelf")

        #expect(store.items.map(\.text) == ["Hello shelf"])
        #expect(store.items.first?.addedAt == fixture.clock.now)
    }

    @Test func convertsImagesToPNGAndRejectsGarbage() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()

        store.add(imageData: Data([1, 2, 3]))
        store.add(imageData: try ShelfFixture.tiffData())

        let data = try #require(store.items.first?.imageData)
        #expect(store.count == 1)
        #expect(data.starts(with: ShelfImageEncoding.pngSignature))
    }

    @Test func removesSingleItemAndAll() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()
        store.add(text: "one")
        store.add(text: "two")
        let removedID = try #require(store.items.first?.id)

        store.remove(removedID)
        #expect(store.items.map(\.text) == ["one"])

        store.removeAll()
        #expect(store.items.isEmpty)
        #expect(!store.hasItems)
        #expect(fixture.reloadedStore().items.isEmpty)
    }

    @Test func removingTextDeletesItsPayloadFile() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()
        store.add(text: "payload")
        let item = try #require(store.items.first)
        let payloadURL = try #require(store.previewURL(for: item))

        store.remove(item.id)

        #expect(!FileManager.default.fileExists(atPath: payloadURL.path(percentEncoded: false)))
    }

    @Test func persistsItemsAcrossInstances() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let file = try fixture.makeFile("report.pdf")
        let png = try ShelfFixture.pngData()
        let store = fixture.makeStore()
        store.add(fileURLs: [file])
        store.add(text: "note")
        store.add(imageData: png)

        let reloaded = fixture.makeStore()
        reloaded.start()
        defer { reloaded.stop() }

        #expect(reloaded.items.map(\.id) == store.items.map(\.id))
        #expect(reloaded.items.map(\.addedAt) == store.items.map(\.addedAt))
        #expect(reloaded.items[0].imageData == png)
        #expect(reloaded.items[1].text == "note")
        #expect(reloaded.items[2].fileURL?.resolvingSymlinksInPath() == file.resolvingSymlinksInPath())
    }

    @Test func mutationBeforeStartKeepsPersistedItems() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        fixture.makeStore().add(text: "old")

        let reloaded = fixture.makeStore()
        reloaded.add(text: "new")

        #expect(reloaded.items.map(\.text) == ["new", "old"])
    }

    @Test func dropsFilesThatNoLongerExist() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let kept = try fixture.makeFile("kept.txt")
        let deleted = try fixture.makeFile("deleted.txt")
        fixture.makeStore().add(fileURLs: [kept, deleted])
        try FileManager.default.removeItem(at: deleted)

        let reloaded = fixture.makeStore()
        reloaded.start()
        defer { reloaded.stop() }

        #expect(reloaded.items.map(\.displayName) == ["kept.txt"])
        #expect(fixture.reloadedStore().items.count == 1)
    }

    @Test func dropsTextWhosePayloadIsMissing() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        fixture.makeStore().add(text: "gone")
        try FileManager.default.removeItem(at: fixture.storageDirectory)

        let reloaded = fixture.makeStore()
        reloaded.start()
        defer { reloaded.stop() }

        #expect(reloaded.items.isEmpty)
    }

    @Test func ignoresCorruptIndex() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(Data("not json".utf8), forKey: "shelf.items")

        let store = fixture.makeStore()
        store.start()
        defer { store.stop() }

        #expect(store.items.isEmpty)
        #expect(fixture.defaults.data(forKey: "shelf.items") == nil)
    }

    @Test func skipsUnknownAndMalformedRecords() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()
        store.add(text: "valid")
        let validID = try #require(store.items.first?.id)
        let json = """
        [{"id":"\(UUID().uuidString)","kind":"hologram","addedAt":0},
         {"kind":"text"},
         {"id":"\(UUID().uuidString)","kind":"file","addedAt":0,"bookmark":"AAAA"},
         {"id":"\(validID.uuidString)","kind":"text","addedAt":\(fixture.clock.now.timeIntervalSinceReferenceDate)}]
        """
        fixture.defaults.set(Data(json.utf8), forKey: "shelf.items")

        let reloaded = fixture.makeStore()
        reloaded.start()
        defer { reloaded.stop() }

        #expect(reloaded.items.map(\.id) == [validID])
        #expect(ShelfRecord.decodeList(from: try #require(fixture.defaults.data(forKey: "shelf.items")))?.count == 1)
    }

    @Test func removesOrphanPayloadsOnLoad() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let orphan = fixture.storageDirectory.appending(path: "\(UUID().uuidString).txt")
        try FileManager.default.createDirectory(at: fixture.storageDirectory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: orphan)

        fixture.makeStore().start()

        #expect(!FileManager.default.fileExists(atPath: orphan.path(percentEncoded: false)))
    }

    @Test func copiesItemsToPasteboard() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let store = fixture.makeStore()
        store.add(text: "copied")

        store.copyToPasteboard(store.items.map(\.id), pasteboard: pasteboard)

        #expect(pasteboard.string(forType: .string) == "copied")
    }

    @Test func pastesFilesImagesAndText() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let store = fixture.makeStore()
        let file = try fixture.makeFile("pasted.txt")

        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        #expect(store.pasteFromClipboard(pasteboard))

        pasteboard.clearContents()
        pasteboard.setData(try ShelfFixture.pngData(), forType: .png)
        #expect(store.pasteFromClipboard(pasteboard))

        pasteboard.clearContents()
        pasteboard.setString("snippet", forType: .string)
        #expect(store.pasteFromClipboard(pasteboard))

        pasteboard.clearContents()
        #expect(!store.pasteFromClipboard(pasteboard))

        #expect(store.items.map(\.text) == ["snippet", nil, nil])
        #expect(store.items[1].imageData != nil)
        #expect(store.items[2].displayName == "pasted.txt")
    }

    @Test func handleDropRejectsWhileDraggingOut() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()
        store.isDraggingOut = true

        #expect(!store.handleDrop(providers: [NSItemProvider(object: "text" as NSString)]))
    }

    @Test func handleDropAcceptsText() async throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()

        #expect(store.handleDrop(providers: [NSItemProvider(object: "dropped" as NSString)]))
        #expect(!store.handleDrop(providers: [NSItemProvider()]))

        for _ in 0..<100 where store.items.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.items.map(\.text) == ["dropped"])
    }
}
