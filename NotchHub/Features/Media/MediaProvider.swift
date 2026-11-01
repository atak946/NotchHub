import Foundation

/// A media player NotchHub can read and control. Implementations must never launch the player.
protocol MediaProvider: Sendable {
    var source: MediaSource { get }
    func isRunning() async -> Bool
    /// `nil` when the player is not running or has nothing loaded.
    func fetchNowPlaying() async throws -> NowPlaying?
    func playPause() async throws
    func next() async throws
    func previous() async throws
    func seek(to position: TimeInterval) async throws
    /// Raw image bytes for the track's artwork, if any.
    func fetchArtwork(for track: NowPlaying) async throws -> Data?
    // Optional commands; a player that lacks one keeps the default no-op and `MediaSource` hides its button.
    func setLiked(_ liked: Bool) async throws
    func setShuffling(_ shuffling: Bool) async throws
    func setRepeatMode(_ mode: RepeatMode) async throws
    /// Player volume, `0...1`.
    func setVolume(_ volume: Double) async throws
    func setPlaybackRate(_ rate: Double) async throws
    func togglePictureInPicture() async throws
}

extension MediaProvider {
    func setLiked(_ liked: Bool) async throws {}
    func setShuffling(_ shuffling: Bool) async throws {}
    func setRepeatMode(_ mode: RepeatMode) async throws {}
    func setVolume(_ volume: Double) async throws {}
    func setPlaybackRate(_ rate: Double) async throws {}
    func togglePictureInPicture() async throws {}
}

/// Shared plumbing for players controlled through AppleScript.
struct AppleScriptBridge: Sendable {
    let bundleIdentifier: String
    let runner: any ScriptRunner
    let appChecker: any RunningApplicationChecking

    func isRunning() async -> Bool {
        await appChecker.isRunning(bundleIdentifier: bundleIdentifier)
    }

    /// Runs `body` inside a tell block, guarded twice against launching the app:
    /// once via NSRunningApplication and once inside the script itself.
    /// Returns `nil` when the player is not running.
    func run(_ body: String) async throws -> ScriptOutput? {
        guard await isRunning() else { return nil }
        do {
            return try await runner.run(Self.wrap(body, bundleIdentifier: bundleIdentifier))
        } catch ScriptError.applicationNotRunning {
            return nil
        }
    }

    static func wrap(_ body: String, bundleIdentifier: String) -> String {
        """
        if application id "\(bundleIdentifier)" is running then
        tell application id "\(bundleIdentifier)"
        \(body)
        end tell
        end if
        return ""
        """
    }

    /// Locale-independent numeric literal for AppleScript source.
    static func literal(_ value: TimeInterval) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

/// AppleScript body that emits one `NowPlayingParser` line. Each optional field is guarded by `try`.
enum PlayerScripts {
    /// `extras` are expressions for the parser's extra fields in order; an empty string leaves that field empty.
    static func nowPlaying(durationProperty: String, artworkExpression: String, extras: [String] = []) -> String {
        let extraFields = extras.enumerated().map { index, expression in
            expression.isEmpty ? "set extra\(index) to \"\"" : """
            set extra\(index) to ""
            try
            set extra\(index) to (\(expression)) as text
            end try
            """
        }
        let extraJoin = extras.indices.map { " & sep & extra\($0)" }.joined()
        return """
        set sep to character id 31
        set playerState to (player state as text)
        if playerState is "stopped" then return playerState
        set trackName to ""
        set trackArtist to ""
        set trackAlbum to ""
        set trackDuration to ""
        set trackPosition to ""
        set trackArtwork to ""
        try
        set trackName to (name of current track) as text
        end try
        try
        set trackArtist to (artist of current track) as text
        end try
        try
        set trackAlbum to (album of current track) as text
        end try
        try
        set trackDuration to (\(durationProperty) of current track) as text
        end try
        try
        set trackPosition to (player position) as text
        end try
        try
        set trackArtwork to (\(artworkExpression)) as text
        end try
        \(extraFields.joined(separator: "\n"))
        return playerState & sep & trackName & sep & trackArtist & sep & trackAlbum & sep & trackDuration & sep & trackPosition & sep & trackArtwork\(extraJoin)
        """
    }

    static func volume(_ volume: Double) -> String {
        "set sound volume to \(Int((min(max(volume, 0), 1) * NowPlayingParser.volumeScale).rounded()))"
    }

    static let playPause = "playpause"
    static let nextTrack = "next track"
    static let previousTrack = "previous track"

    static func seek(to position: TimeInterval) -> String {
        "set player position to \(AppleScriptBridge.literal(position))"
    }
}

struct SpotifyProvider: MediaProvider {
    private static let nowPlayingScript = PlayerScripts.nowPlaying(
        durationProperty: "duration",
        artworkExpression: "artwork url of current track",
        extras: ["", "shuffling", "repeating", "sound volume"]
    )

    private let bridge: AppleScriptBridge
    private let downloader: any ArtworkDownloading

    var source: MediaSource { .spotify }

    init(
        runner: any ScriptRunner = AppleScriptRunner.shared,
        appChecker: any RunningApplicationChecking = WorkspaceRunningApplicationChecker(),
        downloader: any ArtworkDownloading = URLSessionArtworkDownloader()
    ) {
        bridge = AppleScriptBridge(bundleIdentifier: "com.spotify.client", runner: runner, appChecker: appChecker)
        self.downloader = downloader
    }

    func isRunning() async -> Bool { await bridge.isRunning() }

    func fetchNowPlaying() async throws -> NowPlaying? {
        guard let output = try await bridge.run(Self.nowPlayingScript), let text = output.text else { return nil }
        return NowPlayingParser.parse(text, source: .spotify)
    }

    func playPause() async throws { _ = try await bridge.run(PlayerScripts.playPause) }
    func next() async throws { _ = try await bridge.run(PlayerScripts.nextTrack) }
    func previous() async throws { _ = try await bridge.run(PlayerScripts.previousTrack) }
    func seek(to position: TimeInterval) async throws { _ = try await bridge.run(PlayerScripts.seek(to: position)) }

    func fetchArtwork(for track: NowPlaying) async throws -> Data? {
        guard let url = track.artworkURL else { return nil }
        return try await downloader.download(url)
    }

    func setShuffling(_ shuffling: Bool) async throws { _ = try await bridge.run("set shuffling to \(shuffling)") }
    /// Spotify's scripting only knows repeat on/off; "one" repeats the context too.
    func setRepeatMode(_ mode: RepeatMode) async throws { _ = try await bridge.run("set repeating to \(mode != .off)") }
    func setVolume(_ volume: Double) async throws { _ = try await bridge.run(PlayerScripts.volume(volume)) }
}

struct MusicProvider: MediaProvider {
    private static let nowPlayingScript = PlayerScripts.nowPlaying(
        durationProperty: "duration",
        artworkExpression: "persistent ID of current track",
        extras: ["favorited of current track", "shuffle enabled", "song repeat", "sound volume"]
    )
    private static let artworkScript = "return raw data of artwork 1 of current track"

    private let bridge: AppleScriptBridge

    var source: MediaSource { .music }

    init(
        runner: any ScriptRunner = AppleScriptRunner.shared,
        appChecker: any RunningApplicationChecking = WorkspaceRunningApplicationChecker()
    ) {
        bridge = AppleScriptBridge(bundleIdentifier: "com.apple.Music", runner: runner, appChecker: appChecker)
    }

    func isRunning() async -> Bool { await bridge.isRunning() }

    func fetchNowPlaying() async throws -> NowPlaying? {
        guard let output = try await bridge.run(Self.nowPlayingScript), let text = output.text else { return nil }
        return NowPlayingParser.parse(text, source: .music)
    }

    func playPause() async throws { _ = try await bridge.run(PlayerScripts.playPause) }
    func next() async throws { _ = try await bridge.run(PlayerScripts.nextTrack) }
    func previous() async throws { _ = try await bridge.run(PlayerScripts.previousTrack) }
    func seek(to position: TimeInterval) async throws { _ = try await bridge.run(PlayerScripts.seek(to: position)) }

    func fetchArtwork(for track: NowPlaying) async throws -> Data? {
        guard track.artworkID != nil, let output = try await bridge.run(Self.artworkScript) else { return nil }
        return output.data.isEmpty ? nil : output.data
    }

    func setLiked(_ liked: Bool) async throws { _ = try await bridge.run("set favorited of current track to \(liked)") }
    func setShuffling(_ shuffling: Bool) async throws { _ = try await bridge.run("set shuffle enabled to \(shuffling)") }
    func setRepeatMode(_ mode: RepeatMode) async throws { _ = try await bridge.run("set song repeat to \(mode.rawValue)") }
    func setVolume(_ volume: Double) async throws { _ = try await bridge.run(PlayerScripts.volume(volume)) }
}
