import Foundation
import Testing
@testable import NotchHub

struct MediaProviderTests {
    private let allRunning = FakeAppChecker(running: [MediaSource.spotify.bundleIdentifier, MediaSource.music.bundleIdentifier])

    @Test func neverScriptsAPlayerThatIsNotRunning() async throws {
        let runner = FakeScriptRunner()
        let provider = SpotifyProvider(runner: runner, appChecker: FakeAppChecker(running: []), downloader: FakeDownloader(data: Data()))

        let track = try await provider.fetchNowPlaying()
        try await provider.playPause()
        try await provider.seek(to: 10)

        #expect(track == nil)
        #expect(runner.scripts.isEmpty)
    }

    @Test func fetchesAndParsesWithOneScriptCall() async throws {
        let line = TrackFixture.line("playing", "Song", "Artist", "Album", "120000", "3", "https://i.scdn.co/image/a")
        let runner = FakeScriptRunner(outputs: [ScriptOutput(text: line)])
        let provider = SpotifyProvider(runner: runner, appChecker: allRunning, downloader: FakeDownloader(data: Data()))

        let track = try await provider.fetchNowPlaying()

        #expect(track?.title == "Song")
        #expect(track?.duration == 120)
        #expect(runner.scripts.count == 1)
        let script = try #require(runner.scripts.first)
        #expect(script.contains("if application id \"com.spotify.client\" is running then"))
        #expect(script.contains("artwork url of current track"))
    }

    @Test func sendsLocaleIndependentSeekCommand() async throws {
        let runner = FakeScriptRunner()
        let provider = MusicProvider(runner: runner, appChecker: allRunning)

        try await provider.seek(to: 61.5)
        try await provider.next()

        #expect(runner.scripts.count == 2)
        #expect(runner.scripts[0].contains("set player position to 61.500"))
        #expect(runner.scripts[0].contains("tell application id \"com.apple.Music\""))
        #expect(runner.scripts[1].contains("next track"))
    }

    @Test func treatsAppQuittingMidScriptAsNotRunning() async throws {
        let runner = FakeScriptRunner(error: .applicationNotRunning)
        let provider = MusicProvider(runner: runner, appChecker: allRunning)

        #expect(try await provider.fetchNowPlaying() == nil)
    }

    @Test func propagatesPermissionErrors() async {
        let runner = FakeScriptRunner(error: .notPermitted)
        let provider = MusicProvider(runner: runner, appChecker: allRunning)

        await #expect(throws: ScriptError.notPermitted) {
            try await provider.fetchNowPlaying()
        }
    }

    @Test func musicArtworkUsesRawScriptData() async throws {
        let bytes = Data([0xFF, 0xD8, 0xFF])
        let runner = FakeScriptRunner(outputs: [ScriptOutput(text: nil, data: bytes)])
        let provider = MusicProvider(runner: runner, appChecker: allRunning)
        let track = NowPlaying(
            title: "S", artist: "A", album: "B", duration: 1, position: 0, isPlaying: true,
            source: .music, artworkID: "music:1"
        )

        #expect(try await provider.fetchArtwork(for: track) == bytes)
        #expect(runner.scripts.first?.contains("raw data of artwork 1") == true)
    }

    @Test func spotifyArtworkDownloadsURL() async throws {
        let bytes = Data([1, 2, 3])
        let provider = SpotifyProvider(runner: FakeScriptRunner(), appChecker: allRunning, downloader: FakeDownloader(data: bytes))
        let track = NowPlaying(
            title: "S", artist: "A", album: "B", duration: 1, position: 0, isPlaying: true,
            source: .spotify, artworkURL: URL(string: "https://i.scdn.co/x"), artworkID: "https://i.scdn.co/x"
        )

        #expect(try await provider.fetchArtwork(for: track) == bytes)
    }

    @Test func mapsAppleScriptErrorCodes() {
        #expect(ScriptError.from(code: -1743, message: "") == .notPermitted)
        #expect(ScriptError.from(code: -600, message: "") == .applicationNotRunning)
        #expect(ScriptError.from(code: -1728, message: "x") == .executionFailed(code: -1728, message: "x"))
    }
}
