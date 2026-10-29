import Foundation
import Testing
@testable import NotchHub

@MainActor
struct MediaServiceTests {
    private func makeService(_ providers: [FakeMediaProvider], clock: FakeClock = FakeClock()) -> MediaService {
        MediaService(providers: providers, clock: clock, commandRefreshDelay: .zero)
    }

    @Test func startsEmpty() {
        let service = makeService([])
        #expect(service.nowPlaying == nil)
        #expect(!service.hasCompactContent)
        #expect(service.currentPosition == 0)
    }

    @Test func prefersThePlayingPlayerWhenBothRun() async {
        let spotify = FakeMediaProvider(source: .spotify, track: TrackFixture.make(.spotify, isPlaying: false))
        let music = FakeMediaProvider(source: .music, track: TrackFixture.make(.music, isPlaying: true))
        let service = makeService([spotify, music])

        let anyRunning = await service.refresh()

        #expect(anyRunning)
        #expect(service.nowPlaying?.source == .music)
        #expect(service.hasCompactContent)
    }

    @Test func reportsNoRunningPlayers() async {
        let spotify = FakeMediaProvider(source: .spotify, running: false, track: TrackFixture.make(.spotify))
        let service = makeService([spotify])

        let anyRunning = await service.refresh()

        #expect(!anyRunning)
        #expect(service.nowPlaying == nil)
    }

    @Test func clearsTrackWhenPlayerQuits() async {
        let spotify = FakeMediaProvider(source: .spotify, track: TrackFixture.make(.spotify))
        let service = makeService([spotify])
        await service.refresh()

        spotify.update(track: nil, running: false)
        await service.refresh()

        #expect(service.nowPlaying == nil)
    }

    @Test func interpolatesPositionWithInjectedClock() async {
        let clock = FakeClock()
        let spotify = FakeMediaProvider(source: .spotify, track: TrackFixture.make(.spotify, position: 10))
        let service = makeService([spotify], clock: clock)
        await service.refresh()

        clock.advance(by: 3)

        #expect(service.currentPosition == 13)
        #expect(service.position(at: clock.now.addingTimeInterval(1000)) == 200)
    }

    @Test func playPauseUpdatesOptimisticallyAndFreezesPosition() async {
        let clock = FakeClock()
        let spotify = FakeMediaProvider(source: .spotify, track: TrackFixture.make(.spotify, position: 10))
        let service = makeService([spotify], clock: clock)
        await service.refresh()
        clock.advance(by: 2)
        spotify.update(track: TrackFixture.make(.spotify, position: 12, isPlaying: false))

        service.playPause()

        #expect(service.nowPlaying?.isPlaying == false)
        #expect(service.nowPlaying?.position == 12)
        clock.advance(by: 5)
        #expect(service.currentPosition == 12)
        await service.pendingCommand?.value
        #expect(spotify.commands == [.playPause])
    }

    @Test func seekClampsAndForwardsToActiveProvider() async {
        let spotify = FakeMediaProvider(source: .spotify, track: TrackFixture.make(.spotify, isPlaying: false))
        let music = FakeMediaProvider(source: .music, track: TrackFixture.make(.music, duration: 120, isPlaying: true))
        let service = makeService([spotify, music])
        await service.refresh()

        service.seek(to: 500)
        #expect(service.nowPlaying?.position == 120)
        await service.pendingCommand?.value

        service.seek(to: -3)
        await service.pendingCommand?.value

        #expect(music.commands == [.seek(120), .seek(0)])
        #expect(spotify.commands.isEmpty)
    }

    @Test func nextAndPreviousResetPositionAndForward() async {
        let music = FakeMediaProvider(source: .music, track: TrackFixture.make(.music, position: 80))
        let service = makeService([music])
        await service.refresh()
        music.update(track: TrackFixture.make(.music, title: "Next", position: 0))

        service.next()
        #expect(service.nowPlaying?.position == 0)
        await service.pendingCommand?.value
        service.previous()
        await service.pendingCommand?.value

        #expect(music.commands == [.next, .previous])
        #expect(service.nowPlaying?.title == "Next")
    }

    @Test func commandsWithoutTrackDoNothing() async {
        let music = FakeMediaProvider(source: .music, running: false)
        let service = makeService([music])

        service.playPause()
        service.seek(to: 10)
        service.next()

        #expect(service.pendingCommand == nil)
        #expect(music.commands.isEmpty)
    }

    @Test func tracksPermissionDenials() async {
        let music = FakeMediaProvider(source: .music, fetchError: .notPermitted)
        let spotify = FakeMediaProvider(source: .spotify, track: TrackFixture.make(.spotify))
        let service = makeService([spotify, music])

        await service.refresh()

        #expect(service.permissionDeniedSources == [.music])
        #expect(service.nowPlaying?.source == .spotify)
    }
}
