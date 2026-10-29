import Darwin
import Foundation

/// One address entry of a network interface, as reported by `getifaddrs`.
struct ProfilesInterfaceAddress: Equatable, Sendable {
    enum Family: Sendable { case ipv4, ipv6Global, ipv6LinkLocal, other }

    let name: String
    let isUp: Bool
    let isRunning: Bool
    let family: Family
}

/// Heuristic: a VPN is connected when a `utun*` interface is up and has an IPv4 or global IPv6 address.
/// macOS keeps several `utun` interfaces up with link-local IPv6 only (iCloud, Continuity); those are ignored.
enum ProfilesVPNDetector {
    static let tunnelPrefixes = ["utun", "ipsec", "ppp"]

    static func isTunnelUp(_ addresses: [ProfilesInterfaceAddress]) -> Bool {
        addresses.contains { address in
            tunnelPrefixes.contains(where: address.name.hasPrefix)
                && address.isUp && address.isRunning
                && (address.family == .ipv4 || address.family == .ipv6Global)
        }
    }

    static func currentAddresses() -> [ProfilesInterfaceAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var results: [ProfilesInterfaceAddress] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            results.append(ProfilesInterfaceAddress(
                name: String(cString: entry.ifa_name),
                isUp: flags & IFF_UP != 0,
                isRunning: flags & IFF_RUNNING != 0,
                family: family(of: entry.ifa_addr)
            ))
        }
        return results
    }

    private static func family(of address: UnsafeMutablePointer<sockaddr>?) -> ProfilesInterfaceAddress.Family {
        guard let address else { return .other }
        switch Int32(address.pointee.sa_family) {
        case AF_INET:
            return .ipv4
        case AF_INET6:
            let isLinkLocal = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                let bytes = pointer.pointee.sin6_addr.__u6_addr.__u6_addr8
                return bytes.0 == 0xFE && (bytes.1 & 0xC0) == 0x80
            }
            return isLinkLocal ? .ipv6LinkLocal : .ipv6Global
        default:
            return .other
        }
    }
}
