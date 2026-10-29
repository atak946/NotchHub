import Foundation
import OSLog

/// Called on the main thread for every decoded key event; `true` swallows the event.
typealias MediaKeyTapHandler = @MainActor (SystemDefinedKeyEvent, _ isFine: Bool) -> Bool

/// OS boundary: the active event tap that sees media keys before macOS does.
@MainActor
protocol MediaKeyTapping: AnyObject {
    var isInstalled: Bool { get }
    /// `false` when the tap cannot be created (typically missing Accessibility trust).
    func install(handler: @escaping MediaKeyTapHandler) -> Bool
    func remove()
}

/// OS boundary: reads capabilities and performs the volume/brightness change.
@MainActor
protocol MediaKeyControlling: AnyObject {
    func capabilities(for kind: HUDKind) -> MediaKeyCapabilities
    /// Must not block the caller; `completion` runs on the main actor with the new level (or `nil`).
    func perform(_ command: MediaKeyCommand, completion: @escaping @MainActor @Sendable (HUDReading?) -> Void)
}

/// Owns the media key tap's lifecycle: installs it while wanted and trusted, polls for trust, removes it otherwise.
@MainActor
final class MediaKeyCoordinator {
    static let trustPollInterval: Duration = .seconds(3)

    /// The level after a handled key, for the notch HUD.
    var onReading: (@MainActor (HUDReading) -> Void)?

    private(set) var isWanted = false
    var isInstalled: Bool { tap.isInstalled }

    private let tap: any MediaKeyTapping
    private let controller: any MediaKeyControlling
    private let isTrusted: @MainActor () -> Bool
    private let sleep: NotchHUDCenter.Sleeper
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "HUD")
    private var pollTask: Task<Void, Never>?

    init(
        tap: any MediaKeyTapping,
        controller: any MediaKeyControlling,
        isTrusted: @escaping @MainActor () -> Bool,
        sleep: @escaping NotchHUDCenter.Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.tap = tap
        self.controller = controller
        self.isTrusted = isTrusted
        self.sleep = sleep
    }

    /// `wanted` = notch HUD running and the "hide macOS HUD" setting on.
    func setWanted(_ wanted: Bool) {
        isWanted = wanted
        recheck()
    }

    /// Re-evaluates trust and (un)installs the tap. Called by the trust poll.
    func recheck() {
        guard isWanted else {
            stopPolling()
            if tap.isInstalled {
                tap.remove()
                logger.info("Media key tap removed")
            }
            return
        }
        guard !tap.isInstalled else {
            stopPolling()
            return
        }
        guard isTrusted() else {
            startPolling()
            return
        }
        let installed = tap.install { [weak self] event, isFine in
            self?.handle(event, isFine: isFine) ?? false
        }
        if installed {
            logger.info("Media key tap installed")
            stopPolling()
        } else {
            startPolling()
        }
    }

    /// The tap callback: decides synchronously, performs asynchronously.
    func handle(_ event: SystemDefinedKeyEvent, isFine: Bool) -> Bool {
        guard let key = event.key, let kind = MediaKeyPolicy.controlledKind(of: key) else { return false }
        let decision = MediaKeyPolicy.decide(event, isFine: isFine, capabilities: controller.capabilities(for: kind))
        switch decision {
        case .pass:
            return false
        case .consume(let command):
            if let command {
                controller.perform(command) { [weak self] reading in
                    guard let reading else { return }
                    self?.onReading?(reading)
                }
            }
            return true
        }
    }

    // MARK: - Private

    private func startPolling() {
        guard pollTask == nil else { return }
        let sleep = self.sleep
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await sleep(Self.trustPollInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                self.recheck()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
