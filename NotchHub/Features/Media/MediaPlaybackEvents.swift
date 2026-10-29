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

    init(bundleIdentifiers: Set<String> = Set(MediaSource.allCases.map(\.bundleIdentifier))) {
        self.bundleIdentifiers = bundleIdentifiers
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        guard tokens.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        for name in Self.distributedNames {
            observe(distributed, Notification.Name(name), onChange: onChange)
        }
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

/// Safety-net poll pace; the push events above carry most changes.
enum MediaPollPolicy {
    /// A track is playing: catches seeks made in the player and drift of the extrapolated position.
    static let playingInterval: Duration = .seconds(5)
    /// A player runs but nothing plays.
    static let pausedInterval: Duration = .seconds(15)
    /// No player runs; launches are pushed by NSWorkspace.
    static let idleInterval: Duration = .seconds(30)

    static func interval(anyPlayerRunning: Bool, isPlaying: Bool) -> Duration {
        guard anyPlayerRunning else { return idleInterval }
        return isPlaying ? playingInterval : pausedInterval
    }
}
