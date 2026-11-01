import Foundation
import Testing
@testable import NotchHub

struct WebPlayerProviderTests {
    private let arcRunning = FakeAppChecker(running: [MediaBrowser.arc.bundleIdentifier])

    private func provider(
        _ source: MediaSource = .youtubeMusic,
        runner: FakeScriptRunner,
        appChecker: FakeAppChecker? = nil,
        enabled: Bool = true
    ) -> WebPlayerProvider {
        WebPlayerProvider(
            source: source,
            runner: runner,
            appChecker: appChecker ?? arcRunning,
            downloader: FakeDownloader(data: Data()),
            isEnabled: { enabled }
        )
    }

    private func reading(tab: String, state: String = "playing", title: String = "Song") -> ScriptOutput {
        ScriptOutput(text: TrackFixture.line(
            tab, state, title, "Artist", "Album", "200.5", "12", "https://lh3.googleusercontent.com/a",
            "true", "", "one", "40", "1", "Next Song", "Next Artist"
        ))
    }

    @Test func staysSilentWhenDisabled() async throws {
        let runner = FakeScriptRunner()
        let provider = provider(runner: runner, enabled: false)

        #expect(await provider.isRunning() == false)
        #expect(try await provider.fetchNowPlaying() == nil)
        try await provider.playPause()
        #expect(runner.scripts.isEmpty)
    }

    @Test func neverScriptsABrowserThatIsNotRunning() async throws {
        let runner = FakeScriptRunner()
        let provider = provider(runner: runner, appChecker: FakeAppChecker(running: []))

        #expect(try await provider.fetchNowPlaying() == nil)
        #expect(runner.scripts.isEmpty)
    }

    @Test func parsesTabReadingWithExtras() async throws {
        let runner = FakeScriptRunner(outputs: [reading(tab: "42")])
        let track = try #require(try await provider(runner: runner).fetchNowPlaying())

        #expect(track.source == .youtubeMusic)
        #expect(track.title == "Song")
        #expect(track.duration == 200.5)
        #expect(track.artworkURL == URL(string: "https://lh3.googleusercontent.com/a"))
        #expect(track.extras.isLiked == true)
        #expect(track.extras.isShuffling == nil)
        #expect(track.extras.repeatMode == .one)
        #expect(track.extras.volume == 0.4)
        #expect(track.extras.upNext == UpNextTrack(title: "Next Song", artist: "Next Artist"))
        let script = try #require(runner.scripts.first)
        #expect(script.contains("tell application id \"company.thebrowser.Browser\""))
        #expect(script.contains("tabURL starts with \"https://music.youtube.com/\""))
    }

    @Test func sendsCommandsToTheTabLastRead() async throws {
        let runner = FakeScriptRunner(outputs: [reading(tab: "tab-7")])
        let provider = provider(runner: runner)

        _ = try await provider.fetchNowPlaying()
        try await provider.seek(to: 30)

        let command = try #require(runner.scripts.last)
        #expect(command.contains("is \"tab-7\" then"))
        #expect(command.contains("p.seekTo(30.000,true)"))
    }

    @Test func ignoresCommandsBeforeAnyTabWasRead() async throws {
        let runner = FakeScriptRunner()
        try await provider(runner: runner).next()

        #expect(runner.scripts.isEmpty)
    }

    @Test func prefersAPlayingTabAcrossBrowsers() async throws {
        let runner = FakeScriptRunner(outputs: [reading(tab: "1", state: "paused", title: "Arc"), reading(tab: "2", title: "Brave")])
        let checker = FakeAppChecker(running: [MediaBrowser.arc.bundleIdentifier, MediaBrowser.brave.bundleIdentifier])

        let track = try await provider(runner: runner, appChecker: checker).fetchNowPlaying()

        #expect(track?.title == "Brave")
    }

    @Test func reportsDisabledJavaScript() async {
        let message = "Executing JavaScript through AppleScript is turned off."
        let runner = FakeScriptRunner(error: .executionFailed(code: 12, message: message))

        await #expect(throws: ScriptError.javaScriptDisabled) {
            try await provider(runner: runner).fetchNowPlaying()
        }
    }

    @Test func escapesJavaScriptForAppleScript() {
        #expect(WebPlayerScripts.appleScriptString(#"a "b" \c"#) == #""a \"b\" \\c""#)
    }

    @Test func pageScriptsAvoidDoubleQuotes() {
        let scripts = [
            WebPlayerScripts.read(.youtube), WebPlayerScripts.read(.youtubeMusic),
            WebPlayerScripts.playPause(.youtube), WebPlayerScripts.previous(.youtube),
            WebPlayerScripts.setLiked(true), WebPlayerScripts.setRepeatMode(.all), WebPlayerScripts.setVolume(0.5),
        ]
        #expect(scripts.allSatisfy { !$0.contains("\"") })
    }

    @Test func splitsTabIDFromReading() throws {
        let split = try #require(WebPlayerScripts.splitTab(TrackFixture.line("9", "playing", "Song")))
        #expect(split.tabID == "9")
        #expect(split.line == TrackFixture.line("playing", "Song"))
        #expect(WebPlayerScripts.splitTab("") == nil)
    }
}
