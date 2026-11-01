import AppKit
import Foundation

/// Push signals that a player's state may have changed, so polling can stay slow in between.
@MainActor
protocol MediaPlaybackEventSource: AnyObject {
    func start(onChange: @escaping @MainActor () -> Void)
    func stop()
}

/// Spotify and Music broadcast distributed notifications on play, pause and track change; NSWorkspace reports
/// player launches and quits.
@MainActor
final class SystemMediaPlaybackEvents: MediaPlaybackEventSource {
    static let distributedNames = [
        "com.spotify.client.PlaybackStateChanged",
        "com.apple.Music.playerInfo",
    ]

    private let bundleIdentifiers: Set<String>
    private var tokens: [(NotificationCenter, any NSObjectProtocol)] = []
    private var keyMonitor: Any?

    init(bundleIdentifiers: Set<String> = Set(MediaSource.allCases.compactMap(\.bundleIdentifier) + MediaBrowser.bundleIdentifiers)) {
        self.bundleIdentifiers = bundleIdentifiers
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        guard tokens.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        for name in Self.distributedNames {
            observe(distributed, Notification.Name(name), onChange: onChange)
        }
        observeMediaKeys(onChange: onChange)
        let workspace = NSWorkspace.shared.notificationCenter
        let ids = bundleIdentifiers
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observe(workspace, name) { notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                return app?.bundleIdentifier.map(ids.contains) ?? false
            } onChange: { onChange() }
        }
    }

    func stop() {
        for (center, token) in tokens {
            center.removeObserver(token)
        }
        tokens = []
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// Play/pause, next and previous keys may change a browser tab, which pushes nothing; re-read shortly after.
    /// A global monitor only sees events with Accessibility access, which the HUD already asks for.
    private func observeMediaKeys(onChange: @escaping @MainActor () -> Void) {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { event in
            guard MediaKeyChange.isTrackKeyUp(subtype: Int(event.subtype.rawValue), data1: event.data1) else { return }
            Task { @MainActor in
                try? await Task.sleep(for: MediaKeyChange.settleDelay)
                onChange()
            }
        }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        matches: @escaping @Sendable (Notification) -> Bool = { _ in true },
        onChange: @escaping @MainActor () -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { notification in
            guard matches(notification) else { return }
            MainActor.assumeIsolated { onChange() }
        }
        tokens.append((center, token))
    }
}

/// Decodes the hardware play/pause, next and previous keys from an `NSEvent.systemDefined` event.
enum MediaKeyChange {
    /// `NX_KEYTYPE_PLAY`, `NX_KEYTYPE_NEXT`, `NX_KEYTYPE_PREVIOUS`, `NX_KEYTYPE_FAST`, `NX_KEYTYPE_REWIND`.
    static let trackKeyCodes: Set<Int> = [16, 17, 18, 19, 20]
    /// Gives the page time to switch tracks before it is read.
    static let settleDelay: Duration = .milliseconds(500)

    /// Subtype 8 is "aux control button"; `data1` packs the key code and a key-down (0xA) / key-up (0xB) flag.
    static func isTrackKeyUp(subtype: Int, data1: Int) -> Bool {
        guard subtype == 8 else { return false }
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let state = (data1 & 0xFF00) >> 8
        return state == 0xB && trackKeyCodes.contains(keyCode)
    }
}

/// Safety-net poll pace; the push events above carry most changes.
enum MediaPollPolicy {
    /// A track is playing: catches seeks made in the player and drift of the extrapolated position.
    static let playingInterval: Duration = .seconds(5)
    /// A player runs but nothing plays.
    static let pausedInterval: Duration = .seconds(15)
    /// No player runs; launches are pushed by NSWorkspace.
    static let idleInterval: Duration = .seconds(30)
    /// A browser tab is playing. Browsers push nothing, so a skip made in the page is only seen by polling;
    /// one Chrome read takes about 0.25 s.
    static let webPlayingInterval: Duration = .seconds(2)
    /// Poll this long after the playing track is due to end, so an auto-advance shows up at once.
    static let trackEndGrace: Duration = .milliseconds(600)
    /// Never poll faster than this, even when the track end is imminent.
    static let minimumInterval: Duration = .milliseconds(300)

    /// - Parameters:
    ///   - hasPushEvents: The playing source announces its own changes (Spotify, Music).
    ///   - remaining: Seconds left in the playing track, when known.
    static func interval(
        anyPlayerRunning: Bool,
        isPlaying: Bool,
        hasPushEvents: Bool = true,
        remaining: TimeInterval? = nil
    ) -> Duration {
        guard anyPlayerRunning else { return idleInterval }
        guard isPlaying else { return pausedInterval }
        let base = hasPushEvents ? playingInterval : webPlayingInterval
        guard !hasPushEvents, let remaining, remaining.isFinite, remaining > 0 else { return base }
        let untilEnd = Duration.milliseconds(Int64(remaining * 1000)) + trackEndGrace
        return max(min(base, untilEnd), minimumInterval)
    }
}
