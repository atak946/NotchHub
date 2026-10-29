import Foundation
import Testing
@testable import NotchHub

struct PlaybackMathTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func interpolatesWhilePlaying() {
        let position = PlaybackMath.interpolatedPosition(
            base: 10, snapshotDate: start, now: start.addingTimeInterval(2.5), isPlaying: true, duration: 100
        )
        #expect(position == 12.5)
    }

    @Test func doesNotAdvanceWhilePaused() {
        let position = PlaybackMath.interpolatedPosition(
            base: 10, snapshotDate: start, now: start.addingTimeInterval(30), isPlaying: false, duration: 100
        )
        #expect(position == 10)
    }

    @Test func interpolationStopsAtDurationAndIgnoresClockGoingBack() {
        let past = PlaybackMath.interpolatedPosition(
            base: 98, snapshotDate: start, now: start.addingTimeInterval(10), isPlaying: true, duration: 100
        )
        let backwards = PlaybackMath.interpolatedPosition(
            base: 50, snapshotDate: start, now: start.addingTimeInterval(-5), isPlaying: true, duration: 100
        )
        #expect(past == 100)
        #expect(backwards == 50)
    }

    @Test(arguments: [(-5.0, 0.0), (50.0, 50.0), (250.0, 200.0), (Double.nan, 0.0)])
    func clampsSeekTargets(_ input: Double, expected: Double) {
        #expect(PlaybackMath.clamp(input, duration: 200) == expected)
    }

    @Test func unknownDurationOnlyClampsLowerBound() {
        #expect(PlaybackMath.clamp(500, duration: 0) == 500)
        #expect(PlaybackMath.clamp(-1, duration: 0) == 0)
    }

    @Test func convertsBetweenFractionAndPosition() {
        #expect(PlaybackMath.progress(position: 50, duration: 200) == 0.25)
        #expect(PlaybackMath.progress(position: 10, duration: 0) == 0)
        #expect(PlaybackMath.position(forFraction: 0.5, duration: 200) == 100)
        #expect(PlaybackMath.position(forFraction: 1.4, duration: 200) == 200)
        #expect(PlaybackMath.position(forFraction: -1, duration: 200) == 0)
    }

    @Test(arguments: [
        (0.0, "0:00"), (5.9, "0:05"), (65.0, "1:05"), (600.0, "10:00"),
        (3723.0, "1:02:03"), (-4.0, "0:00"), (Double.infinity, "0:00"),
    ])
    func formatsTimes(_ seconds: Double, expected: String) {
        #expect(MediaTimeFormatter.string(from: seconds) == expected)
    }

    @Test func formatsRemainingTime() {
        #expect(MediaTimeFormatter.remainingString(position: 60, duration: 185) == "-2:05")
        #expect(MediaTimeFormatter.remainingString(position: 60.4, duration: 185) == "-2:05")
        #expect(MediaTimeFormatter.remainingString(position: 300, duration: 185) == "-0:00")
        #expect(MediaTimeFormatter.remainingString(position: 10, duration: 0) == "--:--")
    }
}

struct MediaSourceSelectorTests {
    @Test func prefersPlayingTrack() {
        let spotify = TrackFixture.make(.spotify, isPlaying: false)
        let music = TrackFixture.make(.music, isPlaying: true)
        #expect(MediaSourceSelector.select(from: [spotify, music], current: nil) == music)
        #expect(MediaSourceSelector.select(from: [spotify, music], current: .spotify) == music)
    }

    @Test func keepsCurrentSourceWhenBothPlaying() {
        let spotify = TrackFixture.make(.spotify)
        let music = TrackFixture.make(.music)
        #expect(MediaSourceSelector.select(from: [spotify, music], current: .music) == music)
        #expect(MediaSourceSelector.select(from: [spotify, music], current: nil) == spotify)
    }

    @Test func fallsBackToPausedTrack() {
        let spotify = TrackFixture.make(.spotify, isPlaying: false)
        let music = TrackFixture.make(.music, isPlaying: false)
        #expect(MediaSourceSelector.select(from: [spotify, music], current: .music) == music)
        #expect(MediaSourceSelector.select(from: [spotify, music], current: nil) == spotify)
        #expect(MediaSourceSelector.select(from: [], current: .music) == nil)
    }
}

struct BoundedCacheTests {
    @Test func evictsLeastRecentlyUsed() {
        var cache = BoundedCache<String, Int>(capacity: 2)
        cache.insert(1, for: "a")
        cache.insert(2, for: "b")
        _ = cache.value(for: "a")
        cache.insert(3, for: "c")

        #expect(cache.value(for: "a") == 1)
        #expect(cache.value(for: "b") == nil)
        #expect(cache.value(for: "c") == 3)
        #expect(cache.count == 2)
    }
}
