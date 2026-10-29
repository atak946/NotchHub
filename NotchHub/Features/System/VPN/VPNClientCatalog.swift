import Foundation

/// A VPN client app NotchHub knows how to recognise and launch.
struct VPNClient: Identifiable, Equatable, Hashable, Sendable {
    /// Stable key (not shown in the UI).
    let id: String
    let displayName: String
    /// Known bundle identifiers, newest first. The installed app's own identifier is read at runtime too.
    let bundleIdentifiers: [String]
    /// Absolute install locations, most common first.
    let appPaths: [String]
    /// Lowercased fragments matched against running app names when the bundle id is unknown.
    let nameHints: [String]
}

/// Neutral, data-driven list of supported VPN clients. Order is the default preference order.
enum VPNClientCatalog {
    static let all: [VPNClient] = [
        VPNClient(
            id: "cisco",
            displayName: "Cisco Secure Client",
            bundleIdentifiers: ["com.cisco.secureclient.gui", "com.cisco.anyconnect.gui"],
            appPaths: [
                "/Applications/Cisco/Cisco Secure Client.app",
                "/Applications/Cisco/Cisco AnyConnect Secure Mobility Client.app",
            ],
            nameHints: ["cisco secure client", "anyconnect"]
        ),
        VPNClient(
            id: "globalprotect",
            displayName: "GlobalProtect",
            bundleIdentifiers: ["com.paloaltonetworks.GlobalProtect.client"],
            appPaths: ["/Applications/GlobalProtect.app"],
            nameHints: ["globalprotect"]
        ),
        VPNClient(
            id: "forticlient",
            displayName: "FortiClient",
            bundleIdentifiers: ["com.fortinet.FortiClient"],
            appPaths: ["/Applications/FortiClient.app", "/Applications/FortiClientVPN.app"],
            nameHints: ["forticlient"]
        ),
        VPNClient(
            id: "ivanti",
            displayName: "Ivanti Secure Access",
            bundleIdentifiers: ["net.pulsesecure.Pulse-Secure"],
            appPaths: ["/Applications/Ivanti Secure Access.app", "/Applications/Pulse Secure.app"],
            nameHints: ["ivanti secure access", "pulse secure"]
        ),
        VPNClient(
            id: "openvpn",
            displayName: "OpenVPN Connect",
            bundleIdentifiers: ["org.openvpn.client.app"],
            appPaths: ["/Applications/OpenVPN Connect.app", "/Applications/OpenVPN Connect/OpenVPN Connect.app"],
            nameHints: ["openvpn connect"]
        ),
        VPNClient(
            id: "tunnelblick",
            displayName: "Tunnelblick",
            bundleIdentifiers: ["net.tunnelblick.tunnelblick"],
            appPaths: ["/Applications/Tunnelblick.app"],
            nameHints: ["tunnelblick"]
        ),
        VPNClient(
            id: "wireguard",
            displayName: "WireGuard",
            bundleIdentifiers: ["com.wireguard.macos"],
            appPaths: ["/Applications/WireGuard.app"],
            nameHints: ["wireguard"]
        ),
        VPNClient(
            id: "tailscale",
            displayName: "Tailscale",
            bundleIdentifiers: ["io.tailscale.ipn.macsys", "io.tailscale.ipn.macos"],
            appPaths: ["/Applications/Tailscale.app"],
            nameHints: ["tailscale"]
        ),
        VPNClient(
            id: "nordlayer",
            displayName: "NordLayer",
            bundleIdentifiers: ["com.nordlayer.macos"],
            appPaths: ["/Applications/NordLayer.app"],
            nameHints: ["nordlayer"]
        ),
    ]

    /// Shown when no known client is detected.
    static let genericName = "VPN"

    static func client(id: String) -> VPNClient? {
        all.first { $0.id == id }
    }

    static func client(bundleIdentifier: String) -> VPNClient? {
        all.first { $0.bundleIdentifiers.contains(bundleIdentifier) }
    }
}
