import Foundation

/// Player applications NotchHub can read and control.
enum MediaSource: String, CaseIterable, Identifiable, Sendable {
    case spotify
    case music

    var id: String { rawValue }

    var bundleIdentifier: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .music: "com.apple.Music"
        }
    }

    var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Music"
        }
    }
}

/// A snapshot of the track a player reports. `position` is valid at the moment the snapshot was taken.
struct NowPlaying: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval
    let isPlaying: Bool
    let source: MediaSource
    /// Remote artwork (Spotify). `nil` for players that hand out raw image data.
    let artworkURL: URL?
    /// Stable identity of the artwork, used as the image cache key (URL string or track persistent ID).
    let artworkID: String?

    init(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        position: TimeInterval,
        isPlaying: Bool,
        source: MediaSource,
        artworkURL: URL? = nil,
        artworkID: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
        self.isPlaying = isPlaying
        self.source = source
        self.artworkURL = artworkURL
        self.artworkID = artworkID
    }

    /// Identity of the track itself, independent of playback state.
    var trackID: String { [source.rawValue, title, artist, album].joined(separator: "\u{1F}") }

    func with(position: TimeInterval? = nil, isPlaying: Bool? = nil) -> NowPlaying {
        NowPlaying(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: position ?? self.position,
            isPlaying: isPlaying ?? self.isPlaying,
            source: source,
            artworkURL: artworkURL,
            artworkID: artworkID
        )
    }
}
