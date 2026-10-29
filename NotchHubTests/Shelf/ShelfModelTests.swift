import Foundation
import Testing
@testable import NotchHub

struct ShelfModelTests {
    @Test func displayNameUsesFirstLineOfText() {
        let item = ShelfItem(kind: .text("First line\nSecond"), addedAt: .now)
        #expect(item.displayName == "First line")
        #expect(item.text == "First line\nSecond")
        #expect(item.fileURL == nil)
        #expect(!item.isFile)
    }

    @Test func displayNameTruncatesLongText() {
        let item = ShelfItem(kind: .text(String(repeating: "x", count: 500)), addedAt: .now)
        #expect(item.displayName.count == ShelfItem.snippetLength)
    }

    @Test func fileAndImageAccessors() {
        let file = ShelfItem(kind: .file(URL(filePath: "/tmp/a.pdf")), addedAt: .now)
        let image = ShelfItem(kind: .image(Data([1])), addedAt: .now)
        #expect(file.displayName == "a.pdf")
        #expect(file.isFile)
        #expect(image.displayName == "Görsel")
        #expect(image.imageData == Data([1]))
    }

    @Test func pngDataPassesThroughPNG() throws {
        let png = try ShelfFixture.pngDataNonisolated()
        #expect(ShelfImageEncoding.pngData(from: png) == png)
        #expect(ShelfImageEncoding.pngData(from: Data()) == nil)
    }

    @Test func recordRoundTrip() throws {
        let record = ShelfRecord(id: UUID(), kind: .file, addedAt: .now, bookmark: Data([9]))
        let data = try JSONEncoder().encode([record])
        #expect(ShelfRecord.decodeList(from: data) == [record])
        #expect(ShelfRecord.decodeList(from: Data("{}".utf8)) == nil)
    }
}
