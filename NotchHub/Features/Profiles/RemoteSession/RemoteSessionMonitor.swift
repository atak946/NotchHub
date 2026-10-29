import AppKit
import CoreGraphics
import Foundation
import Observation
import OSLog

/// Requires `requiredPolls` consecutive identical readings before the published state flips (anti-flapping).
struct RemoteSessionDebouncer: Sendable, Equatable {
    static let defaultRequiredPolls = 2

    let requiredPolls: Int
    private(set) var isActive = false
    private var pendingCount = 0

    init(requiredPolls: Int = RemoteSessionDebouncer.defaultRequiredPolls) {
        self.requiredPolls = max(1, requiredPolls)
    }

    /// Feeds one poll; returns the new stable value when it changed, else `nil`.
    mutating func feed(_ reading: Bool) -> Bool? {
        guard reading != isActive else {
            pendingCount = 0
            return nil
        }
        pendingCount += 1
        guard pendingCount >= requiredPolls else { return nil }
        pendingCount = 0
        isActive = reading
        return reading
    }
}

/// Polls for "someone is connected to this Mac" (AnyDesk, Screen Sharing, Remote Management). Heuristic.
@MainActor
@Observable
final class RemoteSessionMonitor {
    static let pollInterval: Duration = .seconds(5)
    static let alertKey = "profiles.remoteSession"
    static let anyDeskBundleID = "com.philandro.anydesk"

    private(set) var assessment: RemoteSessionAssessment = .idle
    /// Stable (debounced) state used for the indicator and alerts.
    private(set) var isSessionActive = false
    private(set) var activeSources: [RemoteSessionSource] = []
    /// `kCGSSessionOnConsoleKey` of this login session; `nil` when unavailable. Diagnostic only.
    private(set) var isSessionOnConsole: Bool?

    var hasCompactIndicator: Bool { store.remoteMonitorEnabled && isSessionActive }

    @ObservationIgnored private let store: ProfilesStore
    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let probe: any RemoteSessionProbing
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var debouncer = RemoteSessionDebouncer()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Profiles")

    init(
        store: ProfilesStore,
        alerts: NotchAlertCenter,
        probe: any RemoteSessionProbing = LibprocRemoteSessionProbe(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.store = store
        self.alerts = alerts
        self.probe = probe
        self.sleep = sleep
    }

    var isRunning: Bool { pollTask != nil }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                guard let sleep = self?.sleep else { return }
                try? await sleep(Self.pollInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        debouncer = RemoteSessionDebouncer()
        assessment = .idle
        isSessionActive = false
        activeSources = []
    }

    /// One probe + classification round. Exposed for tests and "Check now".
    func poll() async {
        guard store.remoteMonitorEnabled else {
            if isSessionActive { apply(.idle, forceInactive: true) }
            return
        }
        let probe = self.probe
        let snapshots = await Task.detached(priority: .utility) { probe.snapshots() }.value
        isSessionOnConsole = Self.readConsoleFlag()
        apply(RemoteSessionClassifier.classify(snapshots), forceInactive: false)
    }

    private func apply(_ newAssessment: RemoteSessionAssessment, forceInactive: Bool) {
        assessment = newAssessment
        if forceInactive {
            debouncer = RemoteSessionDebouncer()
            isSessionActive = false
            activeSources = []
            return
        }
        if newAssessment.isActive {
            activeSources = newAssessment.active.map(\.source).sorted()
        }
        guard let changed = debouncer.feed(newAssessment.isActive) else { return }
        isSessionActive = changed
        logger.info("Remote session \(changed ? "started" : "ended", privacy: .public)")
        if changed {
            postStarted()
        } else {
            postEnded()
            activeSources = []
        }
    }

    // MARK: - Alerts

    private func postStarted() {
        guard store.remoteAlertsEnabled else { return }
        let names = activeSources.map(\.title).joined(separator: ", ")
        let canOpenAnyDesk = activeSources.contains(.anyDesk)
        var action: (@MainActor () -> Void)?
        if canOpenAnyDesk {
            action = { @MainActor in
                // activate() is ignored for background apps; opening the bundle brings it forward.
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.anyDeskBundleID) else { return }
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
        alerts.post(NotchAlert(
            module: .status,
            systemImage: "eye.fill",
            title: "\(names.isEmpty ? "Uzak" : names) oturumu etkin",
            subtitle: "Biri bu Mac'i görüntülüyor olabilir (sezgisel)",
            style: .urgent,
            coalescingKey: Self.alertKey,
            autoDismissAfter: nil,
            actionTitle: canOpenAnyDesk ? "AnyDesk'i göster" : nil,
            action: action
        ))
    }

    private func postEnded() {
        guard store.remoteAlertsEnabled else { return }
        alerts.post(NotchAlert(
            module: .status,
            systemImage: "eye.slash",
            title: "Uzak oturum sona erdi",
            style: .success,
            coalescingKey: Self.alertKey
        ))
    }

    private static func readConsoleFlag() -> Bool? {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        return dictionary["kCGSSessionOnConsoleKey"] as? Bool
    }
}
