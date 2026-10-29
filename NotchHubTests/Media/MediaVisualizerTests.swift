import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import NotchHub

struct EqualizerBarGeneratorTests {
    private let times: [TimeInterval] = stride(from: 0.0, to: 20, by: 0.137).map { $0 }

    @Test func sameSeedProducesSameLevels() {
        let first = EqualizerBarGenerator(seed: 42)
        let second = EqualizerBarGenerator(seed: 42)
        for time in times {
            #expect(first.levels(at: time) == second.levels(at: time))
        }
    }

    @Test func differentSeedsDiverge() {
        let first = EqualizerBarGenerator(seed: 1)
        let second = EqualizerBarGenerator(seed: 2)
        let differing = times.filter { first.levels(at: $0) != second.levels(at: $0) }
        #expect(differing.count == times.count)
    }

    @Test func levelsStayInRange() {
        let generator = EqualizerBarGenerator(barCount: 5, seed: 7)
        for time in times {
            let levels = generator.levels(at: time)
            #expect(levels.count == 5)
            #expect(levels.allSatisfy { $0 >= EqualizerBarGenerator.minimumLevel && $0 <= EqualizerBarGenerator.maximumLevel })
        }
    }

    @Test func motionIsContinuous() {
        let generator = EqualizerBarGenerator(seed: 99)
        let frame = 1.0 / 30
        for time in times {
            let now = generator.levels(at: time)
            let next = generator.levels(at: time + frame)
            for (a, b) in zip(now, next) {
                #expect(abs(a - b) < 0.4)
            }
        }
    }

    @Test func barsMoveIndependently() {
        let generator = EqualizerBarGenerator(seed: 3)
        let levels = generator.levels(at: 12.3)
        #expect(Set(levels).count == levels.count)
        #expect(generator.levels(at: 0) != generator.levels(at: 1))
    }

    @Test func restingAndStaticLevels() {
        let generator = EqualizerBarGenerator(barCount: 4, seed: 5)
        #expect(generator.restingLevels == Array(repeating: EqualizerBarGenerator.restingLevel, count: 4))
        #expect(generator.staticLevels == Array(EqualizerBarGenerator.staticPattern.prefix(4)))
        #expect(EqualizerBarGenerator(barCount: 0, seed: 5).levels(at: 1).isEmpty)
    }

    @Test func seededSourceIsDeterministic() {
        var first = SeededRandomSource(seed: 123)
        var second = SeededRandomSource(seed: 123)
        let a = (0..<8).map { _ in first.next() }
        let b = (0..<8).map { _ in second.next() }
        #expect(a == b)
        #expect(Set(a).count == a.count)
    }
}

struct ArtworkTintTests {
    private func solidImage(red: CGFloat, green: CGFloat, blue: CGFloat, size: Int = 16) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(colorSpace: space, components: [red, green, blue, 1])!)
        context?.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context?.makeImage()
    }

    /// Left half one color, right half another.
    private func splitImage() -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(colorSpace: space, components: [1, 0, 0, 1])!)
        context?.fill(CGRect(x: 0, y: 0, width: 8, height: 16))
        context?.setFillColor(CGColor(colorSpace: space, components: [0, 0, 1, 1])!)
        context?.fill(CGRect(x: 8, y: 0, width: 8, height: 16))
        return context?.makeImage()
    }

    @Test func averagesSolidRed() throws {
        let image = try #require(solidImage(red: 1, green: 0, blue: 0))
        let average = try #require(ArtworkTint.averageColor(of: image))
        #expect(average.red > 0.95)
        #expect(average.green < 0.05)
        #expect(average.blue < 0.05)
    }

    @Test func averagesTwoHalves() throws {
        let image = try #require(splitImage())
        let average = try #require(ArtworkTint.averageColor(of: image))
        #expect(abs(average.red - average.blue) < 0.05)
        #expect(average.red > 0.3)
        #expect(average.green < 0.05)
    }

    @Test func saturatedArtworkKeepsItsHue() throws {
        let image = try #require(solidImage(red: 0, green: 0.8, blue: 0))
        let tint = ArtworkTint.tint(for: image)
        #expect(tint.green > 0.75)
        #expect(tint.red < 0.1)
        #expect(tint.blue < 0.1)
    }

    @Test func darkArtworkIsBrightened() throws {
        let image = try #require(solidImage(red: 0, green: 0, blue: 0.3))
        let tint = ArtworkTint.tint(for: image)
        #expect(tint.blue >= ArtworkTint.minimumBrightness - 0.01)
        #expect(tint.red < 0.05)
    }

    @Test(arguments: [(0.0, 0.0, 0.0), (0.5, 0.5, 0.5), (1.0, 1.0, 1.0)])
    func grayArtworkFallsBackToWhite(gray: (Double, Double, Double)) throws {
        let image = try #require(solidImage(red: gray.0, green: gray.1, blue: gray.2))
        #expect(ArtworkTint.tint(for: image) == .white)
    }

    @Test func missingArtworkIsWhite() {
        #expect(ArtworkTint.tint(for: nil) == .white)
        #expect(ArtworkTint.tint(fromAverage: nil) == .white)
    }

    @Test func hsbRoundTrips() {
        let colors = [
            RGBColor(red: 0.9, green: 0.2, blue: 0.1),
            RGBColor(red: 0.1, green: 0.7, blue: 0.4),
            RGBColor(red: 0.3, green: 0.2, blue: 0.95),
            RGBColor(red: 0.8, green: 0.1, blue: 0.7),
        ]
        for color in colors {
            let hsb = color.hsb
            let back = RGBColor(hue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness)
            #expect(abs(back.red - color.red) < 1e-9)
            #expect(abs(back.green - color.green) < 1e-9)
            #expect(abs(back.blue - color.blue) < 1e-9)
        }
    }
}

@MainActor
struct ArtworkTintStoreTests {
    @Test func cachesPerArtwork() async {
        let counter = CallCounter()
        let store = ArtworkTintStore { _ in
            counter.increment()
            return RGBColor(red: 1, green: 0, blue: 0)
        }
        let image = NSImage(size: NSSize(width: 4, height: 4))
        #expect(store.tint(for: image) == .white)

        await store.prepare(image)
        await store.prepare(image)

        #expect(store.tint(for: image) == RGBColor(red: 1, green: 0, blue: 0))
        #expect(counter.value == 1)
        #expect(store.tint(for: nil) == .white)
    }
}

/// Thread-safe call counter for the `@Sendable` extractor stub.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}

struct MediaVisualizerPolicyTests {
    @Test func activity() {
        typealias A = MediaVisualizerActivity
        #expect(A.resolve(isPlaying: true, isVisible: true, isLowPowerMode: false, reduceMotion: false) == .animating)
        #expect(A.resolve(isPlaying: false, isVisible: true, isLowPowerMode: false, reduceMotion: false) == .resting)
        #expect(A.resolve(isPlaying: false, isVisible: false, isLowPowerMode: true, reduceMotion: true) == .resting)
        #expect(A.resolve(isPlaying: true, isVisible: false, isLowPowerMode: false, reduceMotion: false) == .still)
        #expect(A.resolve(isPlaying: true, isVisible: true, isLowPowerMode: true, reduceMotion: false) == .still)
        #expect(A.resolve(isPlaying: true, isVisible: true, isLowPowerMode: false, reduceMotion: true) == .still)
    }

    @Test func fitsBesideArtworkInCompactWing() {
        let placement = MediaVisualizerLayout.placement(
            isEnabled: true, wingWidth: NotchGeometry.compactWingWidth, showsMediaControls: false
        )
        #expect(placement == .beside)
        #expect(MediaVisualizerLayout.artworkSize + MediaVisualizerLayout.besideWidth <= NotchGeometry.compactWingWidth)
    }

    @Test func overlaysArtworkWhenMediaControlsFillTheWing() {
        let placement = MediaVisualizerLayout.placement(
            isEnabled: true, wingWidth: NotchGeometry.mediaControlsWingWidth, showsMediaControls: true
        )
        #expect(placement == .overlay)
    }

    @Test func hiddenWhenDisabledOrNoWing() {
        #expect(MediaVisualizerLayout.placement(isEnabled: false, wingWidth: 104, showsMediaControls: false) == .hidden)
        #expect(MediaVisualizerLayout.placement(isEnabled: true, wingWidth: 0, showsMediaControls: false) == .hidden)
    }
}

@MainActor
struct MediaVisualizerSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "NotchHubTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func enabledByDefault() {
        #expect(SettingsStore(defaults: makeDefaults()).showsMediaVisualizer)
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeDefaults()
        SettingsStore(defaults: defaults).showsMediaVisualizer = false
        #expect(!SettingsStore(defaults: defaults).showsMediaVisualizer)
    }
}
