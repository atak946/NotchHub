import Foundation
@testable import NotchHub

final class FakeScriptRunner: ScriptRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var outputs: [ScriptOutput]
    private var error: ScriptError?
    private var recorded: [String] = []

    init(outputs: [ScriptOutput] = [], error: ScriptError? = nil) {
        self.outputs = outputs
        self.error = error
    }

    var scripts: [String] { lock.withLock { recorded } }

    func run(_ source: String) async throws -> ScriptOutput {
        try lock.withLock {
            recorded.append(source)
            if let error { throw error }
            return outputs.isEmpty ? ScriptOutput(text: "") : outputs.removeFirst()
        }
    }
}

struct FakeAppChecker: RunningApplicationChecking {
    let running: Set<String>

    func isRunning(bundleIdentifier: String) async -> Bool {
        running.contains(bundleIdentifier)
    }
}

struct FakeDownloader: ArtworkDownloading {
    let data: Data

    func download(_ url: URL) async throws -> Data { data }
}

final class FakeMediaProvider: MediaProvider, @unchecked Sendable {
    enum Command: Equatable {
        case playPause, next, previous, seek(TimeInterval)
    }

    let source: MediaSource
    private let lock = NSLock()
    private var running: Bool
    private var track: NowPlaying?
    private var fetchError: ScriptError?
    private var recorded: [Command] = []

    init(source: MediaSource, running: Bool = true, track: NowPlaying? = nil, fetchError: ScriptError? = nil) {
        self.source = source
        self.running = running
        self.track = track
        self.fetchError = fetchError
    }

    var commands: [Command] { lock.withLock { recorded } }

    func update(track: NowPlaying?, running: Bool = true) {
        lock.withLock {
            self.track = track
            self.running = running
        }
    }

    func isRunning() async -> Bool { lock.withLock { running } }

    func fetchNowPlaying() async throws -> NowPlaying? {
        try lock.withLock {
            if let fetchError { throw fetchError }
            return track
        }
    }

    func playPause() async throws { record(.playPause) }
    func next() async throws { record(.next) }
    func previous() async throws { record(.previous) }
    func seek(to position: TimeInterval) async throws { record(.seek(position)) }
    func fetchArtwork(for track: NowPlaying) async throws -> Data? { nil }

    private func record(_ command: Command) {
        lock.withLock { recorded.append(command) }
    }
}

final class FakeClock: MediaClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSinceReferenceDate: 1_000_000)) {
        current = start
    }

    var now: Date { lock.withLock { current } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

enum TrackFixture {
    static func make(
        _ source: MediaSource,
        title: String = "Song",
        duration: TimeInterval = 200,
        position: TimeInterval = 10,
        isPlaying: Bool = true
    ) -> NowPlaying {
        NowPlaying(
            title: title,
            artist: "Artist",
            album: "Album",
            duration: duration,
            position: position,
            isPlaying: isPlaying,
            source: source
        )
    }

    static func line(_ fields: String...) -> String {
        fields.joined(separator: String(NowPlayingParser.separator))
    }
}
