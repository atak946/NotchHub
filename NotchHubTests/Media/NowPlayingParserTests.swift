import Foundation
import Testing
@testable import NotchHub

struct NowPlayingParserTests {
    @Test func parsesSpotifyLineConvertingMilliseconds() throws {
        let line = TrackFixture.line(
            "playing", "Blinding Lights", "The Weeknd", "After Hours", "200040", "42.5",
            "https://i.scdn.co/image/abc"
        )

        let track = try #require(NowPlayingParser.parse(line, source: .spotify))

        #expect(track.title == "Blinding Lights")
        #expect(track.artist == "The Weeknd")
        #expect(track.album == "After Hours")
        #expect(track.duration == 200.04)
        #expect(track.position == 42.5)
        #expect(track.isPlaying)
        #expect(track.source == .spotify)
        #expect(track.artworkURL == URL(string: "https://i.scdn.co/image/abc"))
        #expect(track.artworkID == "https://i.scdn.co/image/abc")
    }

    @Test func parsesMusicLineWithSecondsAndPersistentID() throws {
        let line = TrackFixture.line("paused", "Song", "Artist", "Album", "245.3", "12.0", "ABCDEF0123456789")

        let track = try #require(NowPlayingParser.parse(line, source: .music))

        #expect(track.duration == 245.3)
        #expect(track.position == 12)
        #expect(!track.isPlaying)
        #expect(track.artworkURL == nil)
        #expect(track.artworkID == "music:ABCDEF0123456789")
    }

    @Test func toleratesMissingOptionalFields() throws {
        let track = try #require(NowPlayingParser.parse(TrackFixture.line("playing", "Live Stream"), source: .music))

        #expect(track.title == "Live Stream")
        #expect(track.artist.isEmpty)
        #expect(track.album.isEmpty)
        #expect(track.duration == 0)
        #expect(track.position == 0)
        #expect(track.artworkID == nil)
    }

    @Test func treatsMissingValueAsEmpty() throws {
        let line = TrackFixture.line("playing", "Radio", "missing value", "", "missing value", "3", "missing value")

        let track = try #require(NowPlayingParser.parse(line, source: .music))

        #expect(track.artist.isEmpty)
        #expect(track.duration == 0)
        #expect(track.position == 3)
        #expect(track.artworkID == nil)
    }

    @Test(arguments: ["", "stopped", "garbage", "playing", TrackFixture.line("playing", "  ")])
    func rejectsStoppedOrMalformedOutput(_ output: String) {
        #expect(NowPlayingParser.parse(output, source: .spotify) == nil)
    }

    @Test func rejectsUnknownState() {
        let line = TrackFixture.line("buffering", "Song", "Artist")
        #expect(NowPlayingParser.parse(line, source: .music) == nil)
    }

    @Test func keepsNonASCIIMetadata() throws {
        let line = TrackFixture.line("playing", "Gülümse Kaderine 🎶", "Sezen Aksu", "東京 ラブストーリー", "180000", "1")

        let track = try #require(NowPlayingParser.parse(line, source: .spotify))

        #expect(track.title == "Gülümse Kaderine 🎶")
        #expect(track.artist == "Sezen Aksu")
        #expect(track.album == "東京 ラブストーリー")
    }

    @Test func acceptsCommaDecimalSeparatorFromLocale() throws {
        let line = TrackFixture.line("playing", "Song", "Artist", "Album", "245,5", "12,25", "ID")

        let track = try #require(NowPlayingParser.parse(line, source: .music))

        #expect(track.duration == 245.5)
        #expect(track.position == 12.25)
    }

    @Test func clampsPositionBeyondDuration() throws {
        let line = TrackFixture.line("playing", "Song", "A", "B", "100", "130")
        let track = try #require(NowPlayingParser.parse(line, source: .music))
        #expect(track.position == 100)
    }

    @Test func trimsTrailingNewlineAndWhitespace() throws {
        let line = TrackFixture.line("playing", " Song ", "Artist", "Album", "100", "5", "ID") + "\n"
        let track = try #require(NowPlayingParser.parse(line, source: .music))
        #expect(track.title == "Song")
        #expect(track.artworkID == "music:ID")
    }

    @Test(arguments: [
        ("playing", NowPlayingParser.PlaybackState.playing),
        ("Paused", .paused),
        ("stopped", .stopped),
        ("fast forwarding", .playing),
        ("«constant ****kPSP»", .playing),
        ("«constant ****kPSp»", .paused),
        ("«constant ****kPSS»", .stopped),
    ])
    func mapsPlaybackStates(_ text: String, expected: NowPlayingParser.PlaybackState) {
        #expect(NowPlayingParser.playbackState(from: text) == expected)
    }

    @Test func upgradesHttpArtworkToHttps() {
        #expect(NowPlayingParser.artworkURL(from: "http://i.scdn.co/image/x")?.absoluteString == "https://i.scdn.co/image/x")
        #expect(NowPlayingParser.artworkURL(from: "file:///etc/passwd") == nil)
        #expect(NowPlayingParser.artworkURL(from: "not a url") == nil)
        #expect(NowPlayingParser.artworkURL(from: "") == nil)
    }

    @Test(arguments: [("12.5", 12.5), ("-3", 0.0), ("nan", 0.0), ("inf", 0.0), ("abc", 0.0), ("", 0.0)])
    func parsesNumbersDefensively(_ text: String, expected: Double) {
        #expect(NowPlayingParser.number(from: text) == expected)
    }
}
