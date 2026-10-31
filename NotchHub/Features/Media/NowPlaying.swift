import Foundation

/// Players NotchHub can read and control: native apps and web players running in a browser tab.
enum MediaSource: String, CaseIterable, Identifiable, Sendable {
    case spotify
    case music
    case youtube
    case youtubeMusic

    var id: String { rawValue }

    /// The app to script and launch; `nil` for web players, which live in a browser tab.
    var bundleIdentifier: String? {
        switch self {
        case .spotify: "com.spotify.client"
        case .music: "com.apple.Music"
        case .youtube, .youtubeMusic: nil
        }
    }

    /// Where a web player lives; `nil` for native apps.
    var webURL: URL? {
        switch self {
        case .spotify, .music: nil
        case .youtube: URL(string: "https://www.youtube.com/")
        case .youtubeMusic: URL(string: "https://music.youtube.com/")
        }
    }

    var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Music"
        case .youtube: "YouTube"
        case .youtubeMusic: "YouTube Music"
        }
    }

    var isWebPlayer: Bool { webURL != nil }

    /// Spotify reports track duration in milliseconds; every other player in seconds.
    var reportsDurationInMilliseconds: Bool { self == .spotify }

    /// Artwork arrives as a URL to download rather than raw image data from the player.
    var hasRemoteArtwork: Bool { self != .music }

    /// Native apps expose a "loved" flag; YouTube Music a like button. Plain YouTube likes are not about music.
    var supportsLike: Bool { self == .music || self == .youtubeMusic }

    /// A shuffle on/off state; YouTube Music only offers a one-shot queue shuffle.
    var supportsShuffle: Bool { self == .spotify || self == .music }

    var supportsRepeat: Bool { self != .youtube }

    /// Playback speed and ±10 s skips, which make sense for videos.
    var supportsVideoControls: Bool { self == .youtube }
}

/// Repeat mode as players report it.
enum RepeatMode: String, CaseIterable, Sendable {
    case off
    case all
    case one

    /// Order the repeat button cycles through.
    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// The track that plays after the current one (YouTube Music's queue).
struct UpNextTrack: Equatable, Sendable {
    let title: String
    let artist: String
}

/// Optional player state beyond the track itself. Each field is `nil` when the player does not report it.
struct PlayerExtras: Equatable, Sendable {
    var isLiked: Bool?
    var isShuffling: Bool?
    var repeatMode: RepeatMode?
    /// Player (not system) volume, `0...1`.
    var volume: Double?
    var playbackRate: Double?
    var upNext: UpNextTrack?

    static let none = PlayerExtras()
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
    /// Remote artwork (Spotify, YouTube). `nil` for players that hand out raw image data.
    let artworkURL: URL?
    /// Stable identity of the artwork, used as the image cache key (URL string or track persistent ID).
    let artworkID: String?
    let extras: PlayerExtras

    init(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        position: TimeInterval,
        isPlaying: Bool,
        source: MediaSource,
        artworkURL: URL? = nil,
        artworkID: String? = nil,
        extras: PlayerExtras = .none
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
        self.extras = extras
    }

    /// Identity of the track itself, independent of playback state.
    var trackID: String { [source.rawValue, title, artist, album].joined(separator: "\u{1F}") }

    func with(position: TimeInterval? = nil, isPlaying: Bool? = nil, extras: PlayerExtras? = nil) -> NowPlaying {
        NowPlaying(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: position ?? self.position,
            isPlaying: isPlaying ?? self.isPlaying,
            source: source,
            artworkURL: artworkURL,
            artworkID: artworkID,
            extras: extras ?? self.extras
        )
    }
}
