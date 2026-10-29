import Foundation

enum VPNState: String, Equatable, Sendable {
    case connected
    case disconnected
    case unknown

    var title: String {
        switch self {
        case .connected: "Bağlı"
        case .disconnected: "Bağlı değil"
        case .unknown: "Bilinmiyor"
        }
    }
}

/// Raw system readings used to decide whether a VPN tunnel is up.
struct VPNSample: Equatable, Sendable {
    /// `nil` before the first path update; `false` while the Mac is offline.
    let isNetworkReachable: Bool?
    /// `PrimaryInterface` of `State:/Network/Global/IPv4`.
    let primaryInterface: String?
    /// Up + running tunnel interfaces that carry an IPv4 address.
    let tunnelInterfaces: [String]
}

/// Name-based classification of network interfaces.
enum VPNInterfaceClassifier {
    static let tunnelPrefixes = ["utun", "ipsec", "ppp", "tun", "tap"]

    static func isTunnel(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return tunnelPrefixes.contains { prefix in
            lowered.hasPrefix(prefix) && lowered.dropFirst(prefix.count).allSatisfy(\.isNumber)
        }
    }
}

/// Heuristic: a tunnel with an IPv4 address (split tunnel) or a tunnel as primary interface (full tunnel).
/// macOS keeps several `utun` interfaces for system services, but those only carry IPv6 link-local
/// addresses, which is why only IPv4-carrying tunnels count.
enum VPNClassifier {
    static func state(for sample: VPNSample) -> VPNState {
        guard let reachable = sample.isNetworkReachable else { return .unknown }
        let primaryIsTunnel = sample.primaryInterface.map(VPNInterfaceClassifier.isTunnel) ?? false
        if primaryIsTunnel || !sample.tunnelInterfaces.isEmpty {
            return .connected
        }
        // Offline: the tunnel is necessarily down, but the network monitor already reports that.
        return reachable ? .disconnected : .unknown
    }
}

enum VPNEvent: Equatable, Sendable {
    case dropped
    case reconnected
}

/// Turns committed (debounced) VPN states into user-facing events. `.unknown` never fires and
/// never resets history, so connected → unknown → disconnected still reports a drop.
struct VPNTransitionTracker {
    private(set) var lastKnown: VPNState?
    private(set) var isDropped = false

    mutating func handle(_ state: VPNState) -> VPNEvent? {
        guard state != .unknown else { return nil }
        defer { lastKnown = state }
        switch (lastKnown, state) {
        case (.connected?, .disconnected):
            isDropped = true
            return .dropped
        case (.disconnected?, .connected) where isDropped:
            isDropped = false
            return .reconnected
        default:
            return nil
        }
    }
}
