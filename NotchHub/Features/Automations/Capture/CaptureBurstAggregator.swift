import Foundation

/// A group of detections shown as one alert.
struct CaptureBatch: Equatable, Sendable {
    static let maxNamesInSubtitle = 2

    let detections: [CaptureDetection]

    var urls: [URL] { detections.map(\.url) }
    var screenshots: [CaptureDetection] { detections.filter { $0.kind == .screenshot } }
    var downloads: [CaptureDetection] { detections.filter { $0.kind == .download } }

    var title: String {
        let count = detections.count
        let screenshotCount = screenshots.count
        if count == 1 {
            return screenshotCount == 1
                ? String(localized: "Ekran görüntüsü kaydedildi")
                : String(localized: "İndirme tamamlandı")
        }
        if screenshotCount == count { return String(localized: "\(count) ekran görüntüsü kaydedildi") }
        if screenshotCount == 0 { return String(localized: "\(count) dosya indirildi") }
        return String(localized: "\(count) yeni dosya")
    }

    var subtitle: String {
        let names = detections.map(\.fileName)
        let shown = names.prefix(Self.maxNamesInSubtitle).joined(separator: ", ")
        let hidden = names.count - Self.maxNamesInSubtitle
        return hidden > 0 ? String(localized: "\(shown) ve \(hidden) tane daha") : shown
    }

    var systemImage: String {
        guard let first = detections.first else { return "doc" }
        if detections.count == 1 { return first.systemImage }
        return screenshots.count == detections.count ? "photo.stack" : "square.and.arrow.down.on.square"
    }
}

/// Collects detections arriving in a burst and releases them together once things go quiet.
struct CaptureBurstAggregator: Sendable {
    /// Quiet time after the last detection before the batch is released.
    static let quietWindow: TimeInterval = 1.5
    /// A never-ending burst is still released after this long.
    static let maxHold: TimeInterval = 6

    private(set) var detections: [CaptureDetection] = []
    private var firstAdded: Date?
    private var lastAdded: Date?

    var isEmpty: Bool { detections.isEmpty }

    mutating func add(_ newDetections: [CaptureDetection], now: Date) {
        let known = Set(detections.map(\.url))
        let fresh = newDetections.filter { !known.contains($0.url) }
        guard !fresh.isEmpty else { return }
        detections += fresh
        firstAdded = firstAdded ?? now
        lastAdded = now
    }

    func isDue(now: Date) -> Bool {
        guard let firstAdded, let lastAdded else { return false }
        return now.timeIntervalSince(lastAdded) >= Self.quietWindow || now.timeIntervalSince(firstAdded) >= Self.maxHold
    }

    /// Returns and clears the batch when it is due.
    mutating func flush(now: Date) -> CaptureBatch? {
        guard isDue(now: now) else { return nil }
        let batch = CaptureBatch(detections: detections)
        detections = []
        firstAdded = nil
        lastAdded = nil
        return batch
    }
}
