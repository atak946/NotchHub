import Foundation
import Observation
import OSLog

/// Fetches raw response bodies with their status code; injectable so tests can serve fixtures.
protocol LyricsHTTPFetching: Sendable {
    func data(from url: URL) async throws -> (Data, Int)
}

struct URLSessionLyricsFetcher: LyricsHTTPFetching {
    static let timeout: TimeInterval = 10

    func data(from url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: Self.timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // LRCLIB asks clients to identify themselves.
        request.setValue("NotchHub (https://github.com/atak946/NotchHub)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// Client for lrclib.net, a free lyrics database without API keys.
struct LRCLibClient: Sendable {
    enum ClientError: Error, Equatable {
        case badResponse(statusCode: Int)
    }

    private struct Record: Decodable {
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private static let baseURL = URL(string: "https://lrclib.net/api/")!
    private static let okStatus = 200..<300
    private static let notFoundStatus = 404

    let fetcher: any LyricsHTTPFetching

    init(fetcher: any LyricsHTTPFetching = URLSessionLyricsFetcher()) {
        self.fetcher = fetcher
    }

    /// Exact match on title, artist and duration first, then a looser search (needed for YouTube video titles).
    func lyrics(for track: NowPlaying) async throws -> Lyrics? {
        if !track.artist.isEmpty, track.duration > 0, let exact = try await exactMatch(for: track) {
            return exact
        }
        return try await search(for: track)
    }

    private func exactMatch(for track: NowPlaying) async throws -> Lyrics? {
        var items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))),
        ]
        if !track.album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: track.album))
        }
        guard let data = try await fetch("get", items) else { return nil }
        return Self.lyrics(from: try JSONDecoder().decode(Record.self, from: data))
    }

    private func search(for track: NowPlaying) async throws -> Lyrics? {
        let title = LyricsParser.cleanedTitle(track.title)
        let items = track.source == .youtube
            ? [URLQueryItem(name: "q", value: title)]
            : [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: track.artist)]
        guard let data = try await fetch("search", items) else { return nil }
        let records = try JSONDecoder().decode([Record].self, from: data)
        // Prefer a synced result; fall back to the first with any lyrics.
        let synced = records.lazy.compactMap(Self.lyrics).first { if case .synced = $0 { true } else { false } }
        return synced ?? records.lazy.compactMap(Self.lyrics).first
    }

    private func fetch(_ path: String, _ items: [URLQueryItem]) async throws -> Data? {
        var components = URLComponents(url: Self.baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = items
        guard let url = components?.url else { return nil }
        let (data, status) = try await fetcher.data(from: url)
        if status == Self.notFoundStatus { return nil }
        guard Self.okStatus.contains(status) else { throw ClientError.badResponse(statusCode: status) }
        return data
    }

    private static func lyrics(from record: Record) -> Lyrics? {
        if record.instrumental == true { return .instrumental }
        if let synced = record.syncedLyrics.map(LyricsParser.parse), !synced.isEmpty {
            return .synced(synced)
        }
        let plain = record.plainLyrics?
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []
        return plain.isEmpty ? nil : .plain(plain)
    }
}

/// Loads lyrics for the shown track on demand (only while the lyrics view is open) and caches them per track.
@MainActor
@Observable
final class LyricsService {
    enum State: Equatable {
        case idle
        case loading
        case loaded(Lyrics)
        case notFound
        case failed
    }

    static let cacheCapacity = 24

    private(set) var state: State = .idle

    @ObservationIgnored private let client: LRCLibClient
    @ObservationIgnored private var cache = BoundedCache<String, State>(capacity: LyricsService.cacheCapacity)
    @ObservationIgnored private var loadedTrackID: String?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Lyrics")

    init(client: LRCLibClient = LRCLibClient()) {
        self.client = client
    }

    /// Call from `.task(id: track.trackID)`; cancellation (track change) drops the result.
    func load(for track: NowPlaying) async {
        guard track.trackID != loadedTrackID else { return }
        loadedTrackID = track.trackID
        if let cached = cache.value(for: track.trackID) {
            state = cached
            return
        }
        state = .loading
        let result: State
        do {
            result = try await client.lyrics(for: track).map(State.loaded) ?? .notFound
        } catch {
            loadedTrackID = nil
            guard !Task.isCancelled else { return }
            logger.error("Lyrics lookup failed: \(Self.logSummary(of: error), privacy: .public)")
            state = .failed
            return
        }
        cache.insert(result, for: track.trackID)
        guard !Task.isCancelled, loadedTrackID == track.trackID else { return }
        state = result
    }

    /// Error kind and code only: a `URLError`'s description carries the request URL, whose query holds the
    /// track title and artist, and the log is readable by anyone on the Mac.
    nonisolated static func logSummary(of error: any Error) -> String {
        switch error {
        case let urlError as URLError:
            return "URLError \(urlError.code.rawValue)"
        case LRCLibClient.ClientError.badResponse(let statusCode):
            return "HTTP \(statusCode)"
        default:
            let nsError = error as NSError
            return "\(nsError.domain) \(nsError.code)"
        }
    }
}
