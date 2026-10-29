import Foundation
import Observation
import OSLog

/// Paces the live permission re-check; injectable so tests do not wait.
protocol PermissionPollingClock: Sendable {
    func sleep(for duration: Duration) async throws
}

struct SystemPermissionPollingClock: PermissionPollingClock {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// Observable permission states for the wizard and the diagnostics report.
@MainActor
@Observable
final class PermissionsModel {
    static let pollInterval: Duration = .seconds(2)

    private(set) var rawStatuses: [AppPermission: PermissionStatus] = [:]
    /// Permissions the user asked for this session (drives the Accessibility denial heuristic).
    private(set) var requested: Set<AppPermission> = []
    private(set) var inFlight: Set<AppPermission> = []

    /// Fired when a permission flips to granted, e.g. so the calendar can reload right away.
    @ObservationIgnored var onGranted: (@MainActor (AppPermission) -> Void)?

    @ObservationIgnored private let checker: any PermissionChecking
    @ObservationIgnored private let clock: any PermissionPollingClock
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Onboarding")

    init(
        checker: any PermissionChecking = SystemPermissionChecker(),
        clock: any PermissionPollingClock = SystemPermissionPollingClock()
    ) {
        self.checker = checker
        self.clock = clock
    }

    var isPolling: Bool { pollTask != nil }

    func status(of permission: AppPermission) -> PermissionStatus {
        PermissionStatusMapping.displayed(
            rawStatuses[permission] ?? .notDetermined,
            for: permission,
            wasRequested: requested.contains(permission)
        )
    }

    /// Every permission with its displayed state, in wizard order.
    var allStatuses: [(permission: AppPermission, status: PermissionStatus)] {
        AppPermission.allCases.map { ($0, status(of: $0)) }
    }

    func refresh() async {
        for permission in AppPermission.allCases {
            let status = await checker.status(of: permission)
            apply(status, to: permission)
        }
    }

    func request(_ permission: AppPermission) async {
        guard !inFlight.contains(permission) else { return }
        inFlight = inFlight.union([permission])
        requested = requested.union([permission])
        await checker.request(permission)
        apply(await checker.status(of: permission), to: permission)
        inFlight = inFlight.subtracting([permission])
    }

    func openSettings(for permission: AppPermission) {
        checker.openSettings(for: permission)
    }

    /// Re-checks every `pollInterval` until `stopPolling()`; safe to call repeatedly.
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self, clock] in
            while !Task.isCancelled {
                await self?.refresh()
                do {
                    try await clock.sleep(for: Self.pollInterval)
                } catch {
                    break
                }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func apply(_ status: PermissionStatus, to permission: AppPermission) {
        let previous = rawStatuses[permission]
        guard previous != status else { return }
        var updated = rawStatuses
        updated[permission] = status
        rawStatuses = updated
        if status == .granted, previous != nil {
            logger.info("Permission granted: \(permission.rawValue, privacy: .public)")
            onGranted?(permission)
        }
    }
}
