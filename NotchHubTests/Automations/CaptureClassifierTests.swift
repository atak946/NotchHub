import Foundation
import Testing
@testable import NotchHub

struct CaptureClassifierTests {
    private typealias P = AutomationsPaths

    private let probe = AutomationsFakeProbe()
    private let clock = AutomationsTestClock()
    private var classifier = CaptureClassifier(config: CaptureWatchConfig(
        screenshotFolders: [AutomationsPaths.desktop],
        downloadFolders: [AutomationsPaths.downloads]
    ))

    private mutating func ingest(_ events: CaptureFileEvent...) {
        classifier.ingest(events, now: clock.now, probe: probe)
    }

    private mutating func poll(after seconds: TimeInterval = 0) -> [CaptureDetection] {
        clock.advance(by: seconds)
        return classifier.poll(now: clock.now, probe: probe)
    }

    // MARK: Screenshots

    @Test mutating func macScreenshotHiddenThenRenamed() {
        let hidden = "\(P.desktop)/.Screenshot 2026-10-28 at 10.00.00.png"
        let final = "\(P.desktop)/Screenshot 2026-10-28 at 10.00.00.png"
        probe.put(hidden, size: 2048, created: clock.now)
        ingest(.created(hidden))
        #expect(!classifier.hasPending)

        probe.rename(hidden, to: final)
        ingest(.renamed(hidden), .renamed(final))
        #expect(poll(after: 0.5).isEmpty)
        #expect(poll(after: 0.5) == [CaptureDetection(url: URL(filePath: final), kind: .screenshot)])
        #expect(!classifier.hasPending)
    }

    @Test(arguments: ["png", "jpg", "JPEG", "heic", "tiff"])
    mutating func screenshotExtensions(ext: String) {
        let path = "\(P.desktop)/Shot.\(ext)"
        probe.put(path, size: 10, created: clock.now)
        ingest(.created(path))
        #expect(poll(after: 1).first?.kind == .screenshot)
    }

    @Test mutating func oldImagesAndNonImagesOnDesktopAreIgnored() {
        let old = "\(P.desktop)/Old.png"
        probe.put(old, size: 10, created: clock.now.addingTimeInterval(-6))
        let note = "\(P.desktop)/Notes.txt"
        probe.put(note, size: 10, created: clock.now)
        ingest(.created(old), .created(note))
        #expect(!classifier.hasPending)
    }

    // MARK: Downloads

    @Test(arguments: ["crdownload", "download", "part", "opdownload"])
    mutating func tempSuffixRenamedToFinalName(suffix: String) {
        let temp = "\(P.downloads)/report.pdf.\(suffix)"
        let final = "\(P.downloads)/report.pdf"
        probe.put(temp, size: 100, created: clock.now)
        ingest(.created(temp), .modified(temp))
        #expect(!classifier.hasPending)

        probe.rename(temp, to: final)
        ingest(.renamed(temp), .renamed(final))
        #expect(classifier.pendingPaths == [final])
        #expect(poll(after: 1) == [CaptureDetection(url: URL(filePath: final), kind: .download)])
    }

    @Test mutating func waitsUntilSizeIsStableForOneSecond() {
        let path = "\(P.downloads)/big.zip"
        probe.put(path, size: 100, created: clock.now)
        ingest(.created(path))

        probe.put(path, size: 500, created: clock.now)
        #expect(poll(after: 0.8).isEmpty) // size changed: restart the stability window
        #expect(poll(after: 0.8).isEmpty) // only 0.8 s stable
        #expect(poll(after: 0.3).count == 1)
    }

    @Test mutating func modifiedEventsResetTheStabilityWindow() {
        let path = "\(P.downloads)/big.zip"
        probe.put(path, size: 100, created: clock.now)
        ingest(.created(path))
        clock.advance(by: 0.9)
        probe.put(path, size: 200, created: clock.now)
        ingest(.modified(path))
        #expect(poll(after: 0.5).isEmpty)
        #expect(poll(after: 0.5).count == 1)
    }

    @Test mutating func firefoxPlaceholderWaitsForPartSibling() {
        let final = "\(P.downloads)/movie.mp4"
        let part = "\(P.downloads)/movie.mp4.part"
        probe.put(final, size: 0, created: clock.now)
        probe.put(part, size: 10, created: clock.now)
        ingest(.created(final), .created(part))
        #expect(poll(after: 2).isEmpty) // empty placeholder

        probe.put(final, size: 10, created: clock.now)
        #expect(poll(after: 2).isEmpty) // size changed
        #expect(poll(after: 2).isEmpty) // .part sibling still there

        probe.rename(part, to: final)
        ingest(.renamed(part), .renamed(final))
        #expect(poll(after: 1).count == 1)
    }

    @Test mutating func removedBeforeStableIsDropped() {
        let path = "\(P.downloads)/gone.zip"
        probe.put(path, size: 10, created: clock.now)
        ingest(.created(path))
        probe.remove(path)
        ingest(.removed(path))
        #expect(!classifier.hasPending)
        #expect(poll(after: 2).isEmpty)
    }

    @Test mutating func ignoresHiddenTempSubfolderDirectoryAndOldFiles() {
        let paths = [
            "\(P.downloads)/.DS_Store",
            "\(P.downloads)/~$draft.docx",
            "\(P.downloads)/file.tmp",
            "\(P.downloads)/Sub/inner.zip",
            "/Users/tester/Documents/other.zip",
        ]
        for path in paths {
            probe.put(path, size: 10, created: clock.now)
        }
        let folder = "\(P.downloads)/Folder"
        probe.put(folder, size: 0, created: clock.now, isRegularFile: false)
        let old = "\(P.downloads)/moved-in.zip"
        probe.put(old, size: 10, created: clock.now.addingTimeInterval(-7 * 3600))

        classifier.ingest(paths.map(CaptureFileEvent.created) + [.created(folder), .renamed(old)], now: clock.now, probe: probe)
        #expect(!classifier.hasPending)
    }

    @Test mutating func modifyingAnExistingFileIsNotADownload() {
        let path = "\(P.downloads)/notes.txt"
        probe.put(path, size: 10, created: clock.now)
        ingest(.modified(path))
        #expect(!classifier.hasPending)
    }

    @Test mutating func subfoldersOptIn() {
        classifier.config.includeSubfolders = true
        let inner = "\(P.downloads)/Sub/inner.zip"
        let insideBundle = "\(P.downloads)/x.zip.download/x.zip"
        probe.put(inner, size: 10, created: clock.now)
        probe.put(insideBundle, size: 10, created: clock.now)
        ingest(.created(inner), .created(insideBundle))
        #expect(classifier.pendingPaths == [inner])
    }

    @Test mutating func screenshotWinsWhenFoldersCoincide() {
        classifier.config = CaptureWatchConfig(screenshotFolders: [P.downloads], downloadFolders: [P.downloads])
        let image = "\(P.downloads)/Screen.png"
        let zip = "\(P.downloads)/archive.zip"
        probe.put(image, size: 10, created: clock.now)
        probe.put(zip, size: 10, created: clock.now)
        ingest(.created(image), .created(zip))
        let kinds = Dictionary(uniqueKeysWithValues: poll(after: 1).map { ($0.fileName, $0.kind) })
        #expect(kinds == ["Screen.png": .screenshot, "archive.zip": .download])
    }

    @Test func nameRules() {
        #expect(CaptureClassifier.isIgnoredName(".hidden"))
        #expect(CaptureClassifier.isIgnoredName("a.crdownload"))
        #expect(CaptureClassifier.isIgnoredName("Unconfirmed 1234.crdownload"))
        #expect(!CaptureClassifier.isIgnoredName("report.pdf"))
        #expect(CaptureClassifier.isWatched("/a/b/c.txt", in: ["/a/b"], includeSubfolders: false))
        #expect(!CaptureClassifier.isWatched("/a/bc/c.txt", in: ["/a/b"], includeSubfolders: false))
        #expect(CaptureClassifier.normalized("/a/b/../c/") == "/a/c")
    }
}

struct CaptureBurstAggregatorTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func detection(_ name: String, _ kind: CaptureKind = .download) -> CaptureDetection {
        CaptureDetection(url: URL(filePath: "/tmp/\(name)"), kind: kind)
    }

    @Test func burstBecomesOneBatchAfterQuietWindow() {
        var aggregator = CaptureBurstAggregator()
        aggregator.add([detection("a.zip")], now: start)
        aggregator.add([detection("b.zip"), detection("a.zip")], now: start.addingTimeInterval(1))
        aggregator.add([detection("c.zip")], now: start.addingTimeInterval(2))

        #expect(aggregator.flush(now: start.addingTimeInterval(3)) == nil)
        let batch = aggregator.flush(now: start.addingTimeInterval(3.5))
        #expect(batch?.detections.count == 3)
        #expect(batch?.title == "3 dosya indirildi")
        #expect(batch?.subtitle == "a.zip, b.zip ve 1 tane daha")
        #expect(aggregator.isEmpty)
        #expect(aggregator.flush(now: start.addingTimeInterval(10)) == nil)
    }

    @Test func endlessBurstIsReleasedAfterMaxHold() {
        var aggregator = CaptureBurstAggregator()
        for second in 0...6 {
            aggregator.add([detection("f\(second).zip")], now: start.addingTimeInterval(TimeInterval(second)))
        }
        #expect(aggregator.isDue(now: start.addingTimeInterval(6)))
    }

    @Test func titlesAndSymbols() {
        let shot = CaptureBatch(detections: [detection("s.png", .screenshot)])
        #expect(shot.title == "Ekran görüntüsü kaydedildi")
        #expect(shot.systemImage == "camera.viewfinder")
        #expect(shot.subtitle == "s.png")

        let pdf = CaptureBatch(detections: [detection("r.pdf")])
        #expect(pdf.title == "İndirme tamamlandı")
        #expect(pdf.systemImage == "doc.richtext")

        let shots = CaptureBatch(detections: [detection("1.png", .screenshot), detection("2.png", .screenshot)])
        #expect(shots.title == "2 ekran görüntüsü kaydedildi")
        #expect(shots.systemImage == "photo.stack")

        let mixed = CaptureBatch(detections: [detection("1.png", .screenshot), detection("a.zip")])
        #expect(mixed.title == "2 yeni dosya")
    }

    @Test(arguments: [
        ("zip", "doc.zipper"), ("dmg", "externaldrive"), ("mp4", "film"), ("mp3", "waveform"),
        ("jpg", "photo"), ("txt", "doc.text"), ("unknownext", "doc"),
    ])
    func symbolsByType(ext: String, symbol: String) {
        #expect(CaptureDetection.systemImage(forExtension: ext, kind: .download) == symbol)
    }
}
