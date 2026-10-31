import Foundation

/// Pure parsing of the single delimiter-separated line the player scripts return per poll.
///
/// Field order: state, title, artist, album, duration, position, artwork (URL for Spotify and YouTube, persistent ID
/// for Music), then the optional extras: liked, shuffle, repeat, volume (0–100), rate, up-next title, up-next artist.
enum NowPlayingParser {
    /// ASCII unit separator; never appears in track metadata.
    static let separator: Character = "\u{1F}"
    static let minimumFieldCount = 2
    static let millisecondsPerSecond: TimeInterval = 1000
    static let volumeScale = 100.0

    private enum Field: Int {
        case state, title, artist, album, duration, position, artwork
        case liked, shuffle, repeatMode, volume, rate, upNextTitle, upNextArtist
    }

    enum PlaybackState: Equatable, Sendable {
        case playing
        case paused
        case stopped
    }

    static func parse(_ output: String, source: MediaSource) -> NowPlaying? {
        let fields = output
            .trimmingCharacters(in: .newlines)
            .split(separator: separator, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard fields.count >= minimumFieldCount,
              let state = playbackState(from: fields[Field.state.rawValue]),
              state != .stopped
        else { return nil }

        let title = field(.title, in: fields)
        guard !title.isEmpty else { return nil }

        let rawDuration = number(from: field(.duration, in: fields))
        let duration = source.reportsDurationInMilliseconds ? rawDuration / millisecondsPerSecond : rawDuration
        let position = PlaybackMath.clamp(number(from: field(.position, in: fields)), duration: duration)
        let artwork = field(.artwork, in: fields)

        return NowPlaying(
            title: title,
            artist: field(.artist, in: fields),
            album: field(.album, in: fields),
            duration: duration,
            position: position,
            isPlaying: state == .playing,
            source: source,
            artworkURL: source.hasRemoteArtwork ? artworkURL(from: artwork) : nil,
            artworkID: artworkID(from: artwork, source: source),
            extras: extras(from: fields)
        )
    }

    private static func extras(from fields: [String]) -> PlayerExtras {
        let volume = field(.volume, in: fields)
        let rate = field(.rate, in: fields)
        let upNextTitle = field(.upNextTitle, in: fields)
        return PlayerExtras(
            isLiked: bool(from: field(.liked, in: fields)),
            isShuffling: bool(from: field(.shuffle, in: fields)),
            repeatMode: repeatMode(from: field(.repeatMode, in: fields)),
            volume: volume.isEmpty ? nil : min(number(from: volume) / volumeScale, 1),
            playbackRate: rate.isEmpty ? nil : number(from: rate),
            upNext: upNextTitle.isEmpty ? nil : UpNextTrack(title: upNextTitle, artist: field(.upNextArtist, in: fields))
        )
    }

    static func bool(from text: String) -> Bool? {
        switch text.lowercased() {
        case "true": true
        case "false": false
        default: nil
        }
    }

    /// Spotify only reports a boolean `repeating`, which maps to repeating the whole context.
    static func repeatMode(from text: String) -> RepeatMode? {
        bool(from: text).map { $0 ? .all : .off } ?? RepeatMode(rawValue: text.lowercased())
    }

    /// Accepts both the readable state names and the raw four-char codes AppleScript sometimes leaks.
    static func playbackState(from text: String) -> PlaybackState? {
        switch text.lowercased() {
        case "playing", "fast forwarding", "rewinding": return .playing
        case "paused": return .paused
        case "stopped", "": return .stopped
        default: break
        }
        if text.contains("kPSP") { return .playing }
        if text.contains("kPSp") { return .paused }
        if text.contains("kPSS") { return .stopped }
        return nil
    }

    /// AppleScript coerces reals with the user's locale, so "215,3" is as valid as "215.3".
    static func number(from text: String) -> TimeInterval {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value > 0 else { return 0 }
        return value
    }

    /// Spotify still reports some artwork as plain http; App Transport Security requires https.
    static func artworkURL(from text: String) -> URL? {
        guard var components = URLComponents(string: text), let scheme = components.scheme?.lowercased() else {
            return nil
        }
        guard scheme == "https" || scheme == "http", components.host?.isEmpty == false else { return nil }
        components.scheme = "https"
        return components.url
    }

    private static func artworkID(from text: String, source: MediaSource) -> String? {
        switch source {
        case .spotify, .youtube, .youtubeMusic: artworkURL(from: text)?.absoluteString
        case .music: text.isEmpty || text == "missing value" ? nil : "music:\(text)"
        }
    }

    private static func field(_ field: Field, in fields: [String]) -> String {
        guard fields.indices.contains(field.rawValue) else { return "" }
        let value = fields[field.rawValue]
        return value == "missing value" ? "" : value
    }
}
