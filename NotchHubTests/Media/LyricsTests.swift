import Foundation
import Testing
@testable import NotchHub

struct LyricsParserTests {
    @Test func parsesTimedLinesAndSkipsMetadata() {
        let lrc = """
        [ar:Artist]
        [00:12.50] First
        [00:05.00][01:00.00] Chorus
        [00:20.00]
        """
        let lines = LyricsParser.parse(lrc)

        #expect(lines == [
            LyricLine(time: 5, text: "Chorus"),
            LyricLine(time: 12.5, text: "First"),
            LyricLine(time: 20, text: ""),
            LyricLine(time: 60, text: "Chorus"),
        ])
    }

    @Test(arguments: [(0.0, nil), (4.9, nil), (5.0, 0), (12.6, 1), (999.0, 2)] as [(Double, Int?)])
    func findsTheLineBeingSung(position: Double, expected: Int?) {
        let lines = [LyricLine(time: 5, text: "a"), LyricLine(time: 12, text: "b"), LyricLine(time: 30, text: "c")]
        #expect(LyricsParser.index(at: position, in: lines) == expected)
    }

    @Test func stripsVideoTitleNoise() {
        #expect(LyricsParser.cleanedTitle("Artist - Song (Official Music Video)") == "Artist - Song")
        #expect(LyricsParser.cleanedTitle("Song [Lyrics]") == "Song")
        #expect(LyricsParser.cleanedTitle("Song (feat. X)") == "Song (feat. X)")
    }
}

struct LRCLibClientTests {
    private struct StubFetcher: LyricsHTTPFetching {
        let responses: @Sendable (URL) -> (String, Int)

        func data(from url: URL) async throws -> (Data, Int) {
            let (body, status) = responses(url)
            return (Data(body.utf8), status)
        }
    }

    @Test func usesExactMatchWhenFound() async throws {
        let client = LRCLibClient(fetcher: StubFetcher { url in
            #expect(url.path() == "/api/get")
            return (#"{"syncedLyrics":"[00:01.00] Hi","plainLyrics":"Hi"}"#, 200)
        })

        let lyrics = try await client.lyrics(for: TrackFixture.make(.spotify))

        #expect(lyrics == .synced([LyricLine(time: 1, text: "Hi")]))
    }

    @Test func fallsBackToSearchPreferringSynced() async throws {
        let client = LRCLibClient(fetcher: StubFetcher { url in
            if url.path() == "/api/get" { return ("", 404) }
            return (#"[{"plainLyrics":"Plain"},{"syncedLyrics":"[00:02.00] Synced"}]"#, 200)
        })

        let lyrics = try await client.lyrics(for: TrackFixture.make(.music))

        #expect(lyrics == .synced([LyricLine(time: 2, text: "Synced")]))
    }

    @Test func reportsInstrumentalAndMissing() async throws {
        let instrumental = LRCLibClient(fetcher: StubFetcher { _ in (#"{"instrumental":true}"#, 200) })
        let missing = LRCLibClient(fetcher: StubFetcher { _ in ("[]", 404) })

        #expect(try await instrumental.lyrics(for: TrackFixture.make(.spotify)) == .instrumental)
        #expect(try await missing.lyrics(for: TrackFixture.make(.spotify)) == nil)
    }

    @Test func throwsOnServerError() async {
        let client = LRCLibClient(fetcher: StubFetcher { _ in ("", 500) })

        await #expect(throws: LRCLibClient.ClientError.badResponse(statusCode: 500)) {
            try await client.lyrics(for: TrackFixture.make(.spotify))
        }
    }
}

struct PlayerExtrasParsingTests {
    @Test func parsesSpotifyBooleanRepeatAndVolume() throws {
        let line = TrackFixture.line("playing", "Song", "Artist", "Album", "1000", "0", "", "", "true", "false", "55")
        let extras = try #require(NowPlayingParser.parse(line, source: .spotify)).extras

        #expect(extras.isLiked == nil)
        #expect(extras.isShuffling == true)
        #expect(extras.repeatMode == .off)
        #expect(extras.volume == 0.55)
    }

    @Test func leavesExtrasEmptyForShortLines() throws {
        let line = TrackFixture.line("playing", "Song")
        #expect(try #require(NowPlayingParser.parse(line, source: .music)).extras == .none)
    }

    @Test func cyclesRepeatModes() {
        #expect(RepeatMode.off.next == .all)
        #expect(RepeatMode.all.next == .one)
        #expect(RepeatMode.one.next == .off)
    }
}
