import Foundation
import Observation
import OSLog

/// Persists profiles and Profiles/remote-session settings in UserDefaults (no secrets are stored here).
@MainActor
@Observable
final class ProfilesStore {
    static let maxQuickLaunchProfiles = 6
    static let defaultTerminalBundleID = "com.apple.Terminal"
    static let defaultWorkspaceRoot = (NSHomeDirectory() as NSString).appendingPathComponent("Developer")

    enum Keys {
        static let profiles = "profiles.items"
        static let activeProfileID = "profiles.activeProfileID"
        static let alertsEnabled = "profiles.alertsEnabled"
        static let terminalBundleID = "profiles.terminalBundleID"
        static let vpnAppBundleID = "profiles.vpnAppBundleID"
        static let workspaceRoot = "profiles.workspaceRoot"
        static let remoteMonitorEnabled = "profiles.remoteMonitor.enabled"
        static let remoteAlertsEnabled = "profiles.remoteMonitor.alertsEnabled"
    }

    private(set) var profiles: [ClientProfile] = []

    var activeProfileID: UUID? {
        didSet { defaults.set(activeProfileID?.uuidString, forKey: Keys.activeProfileID) }
    }

    var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: Keys.alertsEnabled) }
    }

    var terminalBundleID: String {
        didSet { defaults.set(terminalBundleID, forKey: Keys.terminalBundleID) }
    }

    /// Preferred VPN client for the "VPN bekle" step; `nil` means the first installed known client.
    /// Stored as a bundle id under the original key, so earlier free-form values keep working.
    var vpnAppBundleID: String? {
        didSet { defaults.set(vpnAppBundleID, forKey: Keys.vpnAppBundleID) }
    }

    var workspaceRoot: String {
        didSet { defaults.set(workspaceRoot, forKey: Keys.workspaceRoot) }
    }

    var remoteMonitorEnabled: Bool {
        didSet { defaults.set(remoteMonitorEnabled, forKey: Keys.remoteMonitorEnabled) }
    }

    var remoteAlertsEnabled: Bool {
        didSet { defaults.set(remoteAlertsEnabled, forKey: Keys.remoteAlertsEnabled) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let installedVPNClients: @MainActor () -> [VPNInstalledClient]
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Profiles")

    init(
        defaults: UserDefaults = .standard,
        installedVPNClients: @escaping @MainActor () -> [VPNInstalledClient] = { VPNClientLocator.installedClients() }
    ) {
        self.defaults = defaults
        self.installedVPNClients = installedVPNClients
        alertsEnabled = defaults.object(forKey: Keys.alertsEnabled) as? Bool ?? true
        terminalBundleID = defaults.string(forKey: Keys.terminalBundleID) ?? Self.defaultTerminalBundleID
        vpnAppBundleID = defaults.string(forKey: Keys.vpnAppBundleID).flatMap { $0.isEmpty ? nil : $0 }
        workspaceRoot = defaults.string(forKey: Keys.workspaceRoot) ?? Self.defaultWorkspaceRoot
        remoteMonitorEnabled = defaults.object(forKey: Keys.remoteMonitorEnabled) as? Bool ?? true
        remoteAlertsEnabled = defaults.object(forKey: Keys.remoteAlertsEnabled) as? Bool ?? true
        profiles = Self.decodeProfiles(defaults.data(forKey: Keys.profiles), logger: logger)
        let storedActive = defaults.string(forKey: Keys.activeProfileID).flatMap(UUID.init(uuidString:))
        activeProfileID = profiles.contains { $0.id == storedActive } ? storedActive : nil
    }

    var activeProfile: ClientProfile? {
        activeProfileID.flatMap(profile(id:))
    }

    var quickLaunchProfiles: [ClientProfile] {
        Array(profiles.prefix(Self.maxQuickLaunchProfiles))
    }

    /// Folders already used by some profile (to hide matching workspace suggestions).
    var usedFolderPaths: Set<String> {
        Set(profiles.flatMap { ($0.steps + $0.deactivateSteps).compactMap(\.action.folderPath) })
    }

    func profile(id: UUID) -> ClientProfile? {
        profiles.first { $0.id == id }
    }

    /// Inserts or replaces by id.
    func save(_ profile: ClientProfile) {
        if profiles.contains(where: { $0.id == profile.id }) {
            profiles = profiles.map { $0.id == profile.id ? profile : $0 }
        } else {
            profiles = profiles + [profile]
        }
        persist()
    }

    func delete(id: UUID) {
        profiles = profiles.filter { $0.id != id }
        if activeProfileID == id { activeProfileID = nil }
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = profiles
        reordered.move(fromOffsets: source, toOffset: destination)
        profiles = reordered
        persist()
    }

    var executorConfiguration: ProfilesExecutorConfiguration {
        ProfilesExecutorConfiguration(terminalBundleID: terminalBundleID, vpnAppBundleID: effectiveVPNAppBundleID)
    }

    /// Known VPN clients installed on this Mac (for the settings picker).
    func availableVPNClients() -> [VPNInstalledClient] {
        installedVPNClients()
    }

    /// The chosen client, or the first installed known client when none is chosen.
    var effectiveVPNAppBundleID: String? {
        vpnAppBundleID ?? installedVPNClients().first?.bundleIdentifier
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(profiles), forKey: Keys.profiles)
        } catch {
            logger.error("Failed to encode profiles: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func decodeProfiles(_ data: Data?, logger: Logger) -> [ClientProfile] {
        guard let data else { return [] }
        do {
            return try JSONDecoder().decode([ClientProfile].self, from: data)
        } catch {
            logger.error("Discarding unreadable profiles: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
