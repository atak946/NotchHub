import AppKit
import Observation
import OSLog

/// Polls the running players, picks the track to show and forwards playback commands.
@MainActor
@Observable
final class MediaService {
    static let activePollInterval: Duration = .seconds(1)
    static let idlePollInterval: Duration = .seconds(5)
    static let defaultCommandRefreshDelay: Duration = .milliseconds(350)
    static let artworkCacheCapacity = 32

    static var defaultProviders: [any MediaProvider] {
        [SpotifyProvider(), MusicProvider()]
    }

    private(set) var nowPlaying: NowPlaying?
    private(set) var artwork: NSImage?
    /// Players for which macOS denied Automation access.
    private(set) var permissionDeniedSources: Set<MediaSource> = []

    /// True while a track is loaded (playing or paused).
    var hasCompactContent: Bool { nowPlaying != nil }

    @ObservationIgnored private let providers: [any MediaProvider]
    @ObservationIgnored private let clock: any MediaClock
    @ObservationIgnored private let commandRefreshDelay: Duration
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Media")
    @ObservationIgnored private var snapshotDate: Date
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var artworkCache = BoundedCache<String, NSImage>(capacity: MediaService.artworkCacheCapacity)
    @ObservationIgnored private var currentArtworkID: String?
    /// Bumped by every command so that polls started earlier cannot overwrite the optimistic state.
    @ObservationIgnored private var commandGeneration = 0
    /// The last command's task, exposed for tests.
    @ObservationIgnored private(set) var pendingCommand: Task<Void, Never>?

    init(
        providers: [any MediaProvider] = MediaService.defaultProviders,
        clock: any MediaClock = SystemMediaClock(),
        commandRefreshDelay: Duration = MediaService.defaultCommandRefreshDelay
    ) {
        self.providers = providers
        self.clock = clock
        self.commandRefreshDelay = commandRefreshDelay
        snapshotDate = clock.now
    }

    // MARK: Lifecycle

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let anyRunning = await self.refresh()
                let interval = anyRunning ? Self.activePollInterval : Self.idlePollInterval
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Position

    /// Playback position extrapolated to `date` from the last poll.
    func position(at date: Date) -> TimeInterval {
        guard let nowPlaying else { return 0 }
        return PlaybackMath.interpolatedPosition(
            base: nowPlaying.position,
            snapshotDate: snapshotDate,
            now: date,
            isPlaying: nowPlaying.isPlaying,
            duration: nowPlaying.duration
        )
    }

    var currentPosition: TimeInterval { position(at: clock.now) }

    // MARK: Commands

    func playPause() {
        guard let provider = activeProvider else { return }
        if let nowPlaying {
            applyOptimistic(nowPlaying.with(position: currentPosition, isPlaying: !nowPlaying.isPlaying))
        }
        perform("playPause") { try await provider.playPause() }
    }

    func next() {
        guard let provider = activeProvider else { return }
        nowPlaying.map { applyOptimistic($0.with(position: 0)) }
        perform("next") { try await provider.next() }
    }

    func previous() {
        guard let provider = activeProvider else { return }
        nowPlaying.map { applyOptimistic($0.with(position: 0)) }
        perform("previous") { try await provider.previous() }
    }

    func seek(to position: TimeInterval) {
        guard let nowPlaying, let provider = provider(for: nowPlaying.source) else { return }
        let target = PlaybackMath.clamp(position, duration: nowPlaying.duration)
        applyOptimistic(nowPlaying.with(position: target))
        perform("seek") { try await provider.seek(to: target) }
    }

    // MARK: Polling

    /// Polls every provider once. Returns whether any player is running.
    @discardableResult
    func refresh() async -> Bool {
        let generation = commandGeneration
        let results = await Self.poll(providers)
        guard generation == commandGeneration else {
            return true
        }
        updatePermissions(from: results)
        let candidates = results.compactMap { result -> NowPlaying? in
            if case .track(let track) = result { return track }
            return nil
        }
        apply(MediaSourceSelector.select(from: candidates, current: nowPlaying?.source))
        return results.contains { if case .notRunning = $0 { false } else { true } }
    }

    private nonisolated static func poll(_ providers: [any MediaProvider]) async -> [ProviderPollResult] {
        await withTaskGroup(of: (Int, ProviderPollResult).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask { (index, await pollOne(provider)) }
            }
            var results = [(Int, ProviderPollResult)]()
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private nonisolated static func pollOne(_ provider: any MediaProvider) async -> ProviderPollResult {
        guard await provider.isRunning() else { return .notRunning }
        do {
            return .track(try await provider.fetchNowPlaying())
        } catch {
            return .failed(provider.source, error as? ScriptError)
        }
    }

    private func updatePermissions(from results: [ProviderPollResult]) {
        var denied = permissionDeniedSources
        for (provider, result) in zip(providers, results) {
            switch result {
            case .failed(let source, let error):
                if error == .notPermitted {
                    if !denied.contains(source) {
                        logger.error("Automation access denied for \(source.displayName, privacy: .public)")
                    }
                    denied.insert(source)
                } else {
                    logger.error("Polling \(source.displayName, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                }
            case .track:
                denied.remove(provider.source)
            case .notRunning:
                break
            }
        }
        if denied != permissionDeniedSources {
            permissionDeniedSources = denied
        }
    }

    // MARK: State

    private var activeProvider: (any MediaProvider)? {
        nowPlaying.flatMap { provider(for: $0.source) }
    }

    private func provider(for source: MediaSource) -> (any MediaProvider)? {
        providers.first { $0.source == source }
    }

    private func apply(_ track: NowPlaying?) {
        snapshotDate = clock.now
        if track != nowPlaying {
            nowPlaying = track
        }
        updateArtwork(for: track)
    }

    private func applyOptimistic(_ track: NowPlaying) {
        commandGeneration += 1
        apply(track)
    }

    private func perform(_ name: String, _ command: @escaping @Sendable () async throws -> Void) {
        let delay = commandRefreshDelay
        pendingCommand = Task { [weak self] in
            do {
                try await command()
            } catch {
                self?.logger.error("Media command \(name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            await self?.refresh()
        }
    }

    // MARK: Artwork

    private func updateArtwork(for track: NowPlaying?) {
        guard let track, let artworkID = track.artworkID else {
            cancelArtwork()
            return
        }
        guard artworkID != currentArtworkID else { return }
        currentArtworkID = artworkID
        artworkTask?.cancel()

        if let cached = artworkCache.value(for: artworkID) {
            artwork = cached
            return
        }
        guard let provider = provider(for: track.source) else { return }
        artworkTask = Task { [weak self] in
            let image = await Self.loadImage(provider: provider, track: track)
            guard !Task.isCancelled else { return }
            self?.finishArtwork(image, for: artworkID)
        }
    }

    private nonisolated static func loadImage(provider: any MediaProvider, track: NowPlaying) async -> Data? {
        do {
            return try await provider.fetchArtwork(for: track)
        } catch {
            Logger(subsystem: AppIdentity.logSubsystem, category: "Media")
                .error("Artwork fetch failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func finishArtwork(_ data: Data?, for artworkID: String) {
        guard artworkID == currentArtworkID else { return }
        guard let data, let image = NSImage(data: data) else {
            logger.debug("No artwork for current track")
            artwork = nil
            return
        }
        artworkCache.insert(image, for: artworkID)
        artwork = image
    }

    private func cancelArtwork() {
        artworkTask?.cancel()
        artworkTask = nil
        currentArtworkID = nil
        if artwork != nil {
            artwork = nil
        }
    }
}
