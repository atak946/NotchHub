import AppKit
import Foundation
import Testing
@testable import NotchHub

struct ClipboardHistoryPolicyTests {
    private let policy = ClipboardHistoryPolicy()

    @Test func insertsNewestFirst() {
        let first = ClipboardEntryFactory.text("a")
        let second = ClipboardEntryFactory.text("b")

        let result = policy.inserting(second, into: [first])

        #expect(result.entries == [second, first])
        #expect(result.evicted.isEmpty)
    }

    @Test func duplicateMovesToTopAndEvictsOldCopy() {
        let old = ClipboardEntryFactory.text("same", at: 1)
        let other = ClipboardEntryFactory.text("other", at: 2)
        let fresh = ClipboardEntryFactory.text("same", at: 3)

        let result = policy.inserting(fresh, into: [other, old])

        #expect(result.entries == [fresh, other])
        #expect(result.evicted == [old])
    }

    @Test func capsEntryCountDroppingOldest() {
        let existing = (0..<ClipboardHistoryPolicy.defaultMaxEntries).map { ClipboardEntryFactory.text("item \($0)") }
        let newest = ClipboardEntryFactory.text("newest")

        let result = policy.inserting(newest, into: existing)

        #expect(result.entries.count == ClipboardHistoryPolicy.defaultMaxEntries)
        #expect(result.entries.first == newest)
        #expect(result.evicted == [existing.last])
    }

    @Test func imageBudgetDropsOldestImagesButKeepsText() {
        let small = ClipboardHistoryPolicy(maxEntries: 10, maxImageBytes: 100, maxTextBytes: 10)
        let oldImage = ClipboardEntryFactory.image(bytes: 60, tag: "old")
        let text = ClipboardEntryFactory.text("note")
        let newImage = ClipboardEntryFactory.image(bytes: 50, tag: "new")

        let result = small.inserting(newImage, into: [text, oldImage])

        #expect(result.entries == [newImage, text])
        #expect(result.evicted == [oldImage])
    }

    @Test func normalizesText() {
        let small = ClipboardHistoryPolicy(maxTextBytes: 5)

        #expect(small.normalizedText("  hi \n") == "hi")
        #expect(small.normalizedText(" \n\t ") == nil)
        #expect(small.normalizedText("123456") == nil)
        #expect(small.normalizedText("çğü") == nil, "limit counts UTF-8 bytes")
    }

    @Test func rejectsEmptyOrOversizedImages() {
        let small = ClipboardHistoryPolicy(maxImageBytes: 10)

        #expect(small.acceptsImage(byteCount: 10))
        #expect(!small.acceptsImage(byteCount: 0))
        #expect(!small.acceptsImage(byteCount: 11))
    }
}

struct ClipboardPrivacyFilterTests {
    private let filter = ClipboardPrivacyFilter()

    @Test(arguments: Array(ClipboardPrivacyFilter.sensitiveTypes))
    func skipsSensitiveMarkerTypes(_ marker: String) {
        #expect(!filter.allowsCapture(types: ["public.utf8-plain-text", marker], frontmostBundleID: "com.apple.TextEdit"))
    }

    @Test(arguments: ["com.1password.1password", "com.bitwarden.desktop", "org.keepassxc.keepassxc",
                      "com.apple.keychainaccess", "com.apple.Passwords", "COM.APPLE.PASSWORDS"])
    func skipsPasswordManagers(_ bundleID: String) {
        #expect(!filter.allowsCapture(types: ["public.utf8-plain-text"], frontmostBundleID: bundleID))
    }

    @Test func allowsOrdinaryCopies() {
        #expect(filter.allowsCapture(types: ["public.utf8-plain-text"], frontmostBundleID: "com.apple.Safari"))
        #expect(filter.allowsCapture(types: ["public.png"], frontmostBundleID: nil))
    }
}

struct ClipboardCaptureKindTests {
    @Test func prefersTextIgnoresFiles() {
        #expect(ClipboardCaptureKind.preferred(for: ["public.utf8-plain-text", "public.tiff"]) == .text)
        #expect(ClipboardCaptureKind.preferred(for: ["public.tiff"]) == .image)
        #expect(ClipboardCaptureKind.preferred(for: ["public.file-url", "public.utf8-plain-text"]) == .none)
        #expect(ClipboardCaptureKind.preferred(for: ["com.adobe.pdf"]) == .none)
    }

    @Test func pollSlowsDownWhileIdle() {
        #expect(ClipboardPollSchedule.interval(isIdle: false).interval == .milliseconds(750))
        #expect(ClipboardPollSchedule.interval(isIdle: true).interval == .seconds(3))
        #expect(ClipboardPollSchedule.interval(isIdle: false).tolerance > .zero)
    }

    @Test func relativeTime() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        #expect(ClipboardRelativeTime.text(for: now.addingTimeInterval(-10), now: now) == "şimdi")
        #expect(ClipboardRelativeTime.text(for: now.addingTimeInterval(-300), now: now) == "5 dk")
        #expect(ClipboardRelativeTime.text(for: now.addingTimeInterval(-7200), now: now) == "2 sa")
        #expect(ClipboardRelativeTime.text(for: now.addingTimeInterval(-172_800), now: now) == "2 g")
        #expect(ClipboardRelativeTime.text(for: now.addingTimeInterval(60), now: now) == "şimdi")
    }

    @Test func downscalesLargeImagesToPNG() throws {
        let large = try ShelfFixture.pngDataNonisolated(side: 64)

        let png = try #require(ClipboardImageProcessor.downscaledPNG(from: large, maxPixelSide: 16))
        let rep = try #require(NSBitmapImageRep(data: png))

        #expect(png.starts(with: ShelfImageEncoding.pngSignature))
        #expect(max(rep.pixelsWide, rep.pixelsHigh) == 16)
        #expect(ClipboardImageProcessor.downscaledPNG(from: Data([1, 2, 3])) == nil)
    }
}
