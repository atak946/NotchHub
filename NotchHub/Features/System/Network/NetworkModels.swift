import Foundation

enum NetworkInterfaceKind: String, Equatable, Sendable {
    case wifi
    case ethernet
    case cellular
    case loopback
    case other
    case none

    var displayName: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .ethernet: "Ethernet"
        case .cellular: String(localized: "Hücresel")
        case .loopback: "Loopback"
        case .other: String(localized: "Diğer")
        case .none: String(localized: "Ağ yok")
        }
    }

    var systemImage: String {
        switch self {
        case .wifi: "wifi"
        case .ethernet: "cable.connector"
        case .cellular: "antenna.radiowaves.left.and.right"
        case .loopback, .other: "network"
        case .none: "wifi.slash"
        }
    }
}

/// One reading of the network path.
struct NetworkSnapshot: Equatable, Sendable {
    static let offline = NetworkSnapshot(isOnline: false, interface: .none)

    let isOnline: Bool
    let interface: NetworkInterfaceKind
    let isExpensive: Bool
    let isConstrained: Bool
    /// Only available when Location access was already granted.
    let ssid: String?

    init(
        isOnline: Bool,
        interface: NetworkInterfaceKind,
        isExpensive: Bool = false,
        isConstrained: Bool = false,
        ssid: String? = nil
    ) {
        self.isOnline = isOnline
        self.interface = interface
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.ssid = ssid
    }

    /// "Office-5G" when the SSID is known, otherwise the interface type ("Wi-Fi").
    var displayName: String {
        guard isOnline else { return String(localized: "Çevrimdışı") }
        if interface == .wifi, let ssid, !ssid.isEmpty { return ssid }
        return interface.displayName
    }
}

/// Picks the physical interface of a path. NWPath orders interfaces by preference, and a VPN
/// tunnel (`.other`) may come first, so physical interfaces win over tunnels.
enum NetworkClassifier {
    private static let physical: Set<NetworkInterfaceKind> = [.wifi, .ethernet, .cellular]

    static func primaryKind(of kinds: [NetworkInterfaceKind], isSatisfied: Bool) -> NetworkInterfaceKind {
        guard isSatisfied else { return .none }
        if let physicalKind = kinds.first(where: physical.contains) { return physicalKind }
        if kinds.contains(.other) { return .other }
        return kinds.first ?? .none
    }
}

enum NetworkEvent: Equatable, Sendable {
    case wentOffline
    case backOnline(NetworkSnapshot)
    case changed(NetworkSnapshot)
}

/// Which alert, if any, a committed network change deserves. The first snapshot is the baseline.
enum NetworkAlertPolicy {
    static func event(from old: NetworkSnapshot?, to new: NetworkSnapshot) -> NetworkEvent? {
        guard let old else { return nil }
        switch (old.isOnline, new.isOnline) {
        case (true, false):
            return .wentOffline
        case (false, true):
            return .backOnline(new)
        case (true, true) where old.interface != new.interface || old.ssid != new.ssid:
            return .changed(new)
        default:
            return nil
        }
    }
}
