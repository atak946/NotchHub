import Foundation

enum RemoteSessionSource: String, CaseIterable, Sendable, Comparable {
    case anyDesk
    case screenSharing
    case remoteManagement

    var title: String {
        switch self {
        case .anyDesk: "AnyDesk"
        case .screenSharing: String(localized: "Ekran Paylaşımı")
        case .remoteManagement: String(localized: "Uzaktan Yönetim")
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
    }
}

enum RemoteTCPState: Sendable, Equatable {
    case established
    case listening
    case other
}

/// Remote address of a TCP socket, raw bytes in network order.
enum RemoteSocketAddress: Sendable, Equatable {
    case ipv4([UInt8])
    case ipv6([UInt8])

    var isLoopbackOrUnspecified: Bool {
        switch self {
        case let .ipv4(bytes):
            return bytes.first == 127 || bytes.allSatisfy { $0 == 0 }
        case let .ipv6(bytes):
            if bytes.allSatisfy({ $0 == 0 }) { return true }
            if bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1 { return true }
            // IPv4-mapped (::ffff:a.b.c.d): judge the embedded IPv4 address.
            if bytes.count == 16, bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
                return RemoteSocketAddress.ipv4(Array(bytes.suffix(4))).isLoopbackOrUnspecified
            }
            return false
        }
    }
}

/// Parsed TCP socket of one process (from `proc_pidfdinfo`).
struct RemoteTCPSocket: Sendable, Equatable {
    let state: RemoteTCPState
    let localPort: UInt16
    let remotePort: UInt16
    let remoteAddress: RemoteSocketAddress

    var isEstablishedToRemoteHost: Bool {
        state == .established && !remoteAddress.isLoopbackOrUnspecified
    }
}

/// What we could learn about one process.
struct RemoteProcessSnapshot: Sendable, Equatable {
    enum Sockets: Sendable, Equatable {
        case inspected([RemoteTCPSocket])
        /// libproc refused (e.g. root-owned daemon without privileges).
        case unavailable
    }

    let source: RemoteSessionSource
    let pid: Int32
    let sockets: Sockets
}

enum RemoteDetectionEvidence: Sendable, Equatable {
    /// Established TCP connection(s) to a non-loopback peer.
    case connections(Int)
    /// Only the process is visible; its sockets could not be inspected.
    case processOnly
}

struct RemoteSessionDetection: Sendable, Equatable {
    let source: RemoteSessionSource
    let evidence: RemoteDetectionEvidence
}

struct RemoteSessionAssessment: Sendable, Equatable {
    static let idle = RemoteSessionAssessment(active: [], runningSources: [], uninspectableSources: [])

    let active: [RemoteSessionDetection]
    /// Sources whose process is running (session or not).
    let runningSources: Set<RemoteSessionSource>
    /// Sources running but not inspectable: detection fell back to "process running".
    let uninspectableSources: Set<RemoteSessionSource>

    var isActive: Bool { !active.isEmpty }
    var isDegraded: Bool { !uninspectableSources.isEmpty }
}

/// Pure classification of process/socket snapshots into "someone is connected". Heuristic by nature.
enum RemoteSessionClassifier {
    /// AnyDesk keeps one long-lived connection to its relay network while idle.
    static let anyDeskIdleConnections = 1
    /// AnyDesk direct (LAN / port-forwarded) sessions use TCP 7070.
    static let anyDeskDirectPort: UInt16 = 7070
    /// VNC / Apple Screen Sharing.
    static let screenSharingPort: UInt16 = 5900

    static func classify(_ snapshots: [RemoteProcessSnapshot]) -> RemoteSessionAssessment {
        let bySource = Dictionary(grouping: snapshots, by: \.source)
        var active: [RemoteSessionDetection] = []
        var uninspectable: Set<RemoteSessionSource> = []

        for source in RemoteSessionSource.allCases {
            guard let processes = bySource[source], !processes.isEmpty else { continue }
            let sockets = processes.compactMap { snapshot -> [RemoteTCPSocket]? in
                if case let .inspected(sockets) = snapshot.sockets { return sockets }
                return nil
            }
            let anyUnavailable = processes.contains { $0.sockets == .unavailable }
            if anyUnavailable { uninspectable.insert(source) }
            if let detection = detect(source, socketsPerProcess: sockets, anyUnavailable: anyUnavailable) {
                active.append(detection)
            }
        }
        return RemoteSessionAssessment(
            active: active,
            runningSources: Set(bySource.keys),
            uninspectableSources: uninspectable
        )
    }

    private static func detect(
        _ source: RemoteSessionSource,
        socketsPerProcess: [[RemoteTCPSocket]],
        anyUnavailable: Bool
    ) -> RemoteSessionDetection? {
        let remotePerProcess = socketsPerProcess.map { $0.filter(\.isEstablishedToRemoteHost) }
        let remote = remotePerProcess.flatMap { $0 }
        let anyInspected = !socketsPerProcess.isEmpty
        switch source {
        case .anyDesk:
            // Judged per process: each AnyDesk process may hold its own idle relay connection.
            let usesDirectPort = remote.contains { $0.localPort == anyDeskDirectPort || $0.remotePort == anyDeskDirectPort }
            let busiestProcess = remotePerProcess.map(\.count).max() ?? 0
            if usesDirectPort || busiestProcess > anyDeskIdleConnections {
                return RemoteSessionDetection(source: source, evidence: .connections(remote.count))
            }
            // AnyDesk runs permanently; "process running" alone says nothing about a session.
            return nil
        case .screenSharing:
            if !remote.isEmpty { return RemoteSessionDetection(source: source, evidence: .connections(remote.count)) }
            // screensharingd is launched on demand, so a running, uninspectable daemon is a meaningful hint.
            return anyUnavailable && !anyInspected ? RemoteSessionDetection(source: source, evidence: .processOnly) : nil
        case .remoteManagement:
            let viewers = remote.filter { $0.localPort == screenSharingPort }
            return viewers.isEmpty ? nil : RemoteSessionDetection(source: source, evidence: .connections(viewers.count))
        }
    }
}
