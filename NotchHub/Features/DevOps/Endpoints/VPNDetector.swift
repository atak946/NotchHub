import Darwin
import Foundation

/// Answers whether a VPN tunnel is currently up, injectable for tests.
protocol VPNDetector: Sendable {
    func isVPNActive() -> Bool
}

/// One address of a network interface, as seen by `getifaddrs`.
struct DevOpsInterfaceAddress: Equatable, Sendable {
    enum Family: Equatable, Sendable {
        case ipv4
        case ipv6(isLinkLocal: Bool)
        case other
    }

    let name: String
    let isUp: Bool
    let family: Family
}

/// Heuristic: macOS always keeps a few `utun` interfaces for system services (iCloud Private Relay, Handoff…)
/// with only IPv6 link-local addresses. A tunnel counts as VPN when a `utun`/`ipsec`/`ppp` interface is up
/// and has an IPv4 or a routable IPv6 address.
enum VPNInterfaceHeuristic {
    static let tunnelPrefixes = ["utun", "ipsec", "ppp"]

    static func isVPNActive(_ addresses: [DevOpsInterfaceAddress]) -> Bool {
        addresses.contains { address in
            guard address.isUp, tunnelPrefixes.contains(where: address.name.hasPrefix) else { return false }
            switch address.family {
            case .ipv4: return true
            case .ipv6(let isLinkLocal): return !isLinkLocal
            case .other: return false
            }
        }
    }
}

struct InterfaceVPNDetector: VPNDetector {
    func isVPNActive() -> Bool {
        VPNInterfaceHeuristic.isVPNActive(Self.interfaceAddresses())
    }

    static func interfaceAddresses() -> [DevOpsInterfaceAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var result: [DevOpsInterfaceAddress] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let interface = entry.pointee
            let name = String(cString: interface.ifa_name)
            let isUp = (interface.ifa_flags & UInt32(IFF_UP)) != 0
            result.append(DevOpsInterfaceAddress(name: name, isUp: isUp, family: family(of: interface.ifa_addr)))
            cursor = interface.ifa_next
        }
        return result
    }

    private static func family(of address: UnsafeMutablePointer<sockaddr>?) -> DevOpsInterfaceAddress.Family {
        guard let address else { return .other }
        switch Int32(address.pointee.sa_family) {
        case AF_INET:
            return .ipv4
        case AF_INET6:
            let isLinkLocal = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                let bytes = pointer.pointee.sin6_addr.__u6_addr.__u6_addr8
                return bytes.0 == 0xFE && (bytes.1 & 0xC0) == 0x80
            }
            return .ipv6(isLinkLocal: isLinkLocal)
        default:
            return .other
        }
    }
}
