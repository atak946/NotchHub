import AppKit
import Foundation

/// A known VPN client found on disk.
struct VPNInstalledClient: Equatable, Sendable {
    let client: VPNClient
    let appURL: URL
    /// Read from the app's Info.plist; falls back to the catalog's first identifier.
    let bundleIdentifier: String

    var displayName: String { client.displayName }
}

/// Finds known VPN clients on disk and among running apps.
enum VPNClientLocator {
    /// Resolves where a client is installed; injectable for tests.
    typealias AppURLResolver = @MainActor (VPNClient) -> URL?

    /// Installed known clients in catalog order.
    @MainActor
    static func installedClients(
        catalog: [VPNClient] = VPNClientCatalog.all,
        resolve: AppURLResolver = liveAppURL(for:)
    ) -> [VPNInstalledClient] {
        catalog.compactMap { client in
            guard let url = resolve(client) else { return nil }
            let identifier = bundleIdentifier(appURL: url) ?? client.bundleIdentifiers.first ?? client.id
            return VPNInstalledClient(client: client, appURL: url, bundleIdentifier: identifier)
        }
    }

    /// First existing install path, else a Launch Services lookup by bundle id.
    @MainActor
    static func liveAppURL(for client: VPNClient) -> URL? {
        let fileManager = FileManager.default
        if let path = client.appPaths.first(where: { fileManager.fileExists(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }
        return client.bundleIdentifiers.lazy
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .first
    }

    /// Reads `CFBundleIdentifier` from the app's Info.plist; `nil` if it is not installed.
    static func bundleIdentifier(appURL: URL) -> String? {
        let plistURL = appURL.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["CFBundleIdentifier"] as? String
    }

    /// The first running app that is a known client, matched by bundle id (catalog or installed) or by name.
    static func runningClient(
        in apps: [SystemRunningApp],
        installed: [VPNInstalledClient] = [],
        catalog: [VPNClient] = VPNClientCatalog.all
    ) -> VPNClient? {
        for app in apps {
            if let client = match(app, installed: installed, catalog: catalog) { return client }
        }
        return nil
    }

    private static func match(
        _ app: SystemRunningApp,
        installed: [VPNInstalledClient],
        catalog: [VPNClient]
    ) -> VPNClient? {
        if let identifier = app.bundleIdentifier {
            if let hit = installed.first(where: { $0.bundleIdentifier == identifier }) { return hit.client }
            if let hit = catalog.first(where: { $0.bundleIdentifiers.contains(identifier) }) { return hit }
        }
        guard let name = app.name?.lowercased() else { return nil }
        return catalog.first { client in client.nameHints.contains { name.contains($0) } }
    }
}
