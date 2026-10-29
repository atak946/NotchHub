import Darwin
import Foundation

/// Collects snapshots of remote-access processes. Called off the main actor.
protocol RemoteSessionProbing: Sendable {
    func snapshots() -> [RemoteProcessSnapshot]
}

/// Uses the public libproc API (`proc_listallpids`, `proc_pidpath`, `proc_pidinfo`, `proc_pidfdinfo`).
/// Socket details of root-owned daemons are normally not readable without privileges → `.unavailable`.
struct LibprocRemoteSessionProbe: RemoteSessionProbing {
    static let pidHeadroom = 64
    static let fdHeadroom = 16
    static let maxPathLength = 4 * 1024 // PROC_PIDPATHINFO_MAXSIZE

    func snapshots() -> [RemoteProcessSnapshot] {
        // One path buffer for the whole scan instead of a 4 KB allocation per process.
        var buffer = [CChar](repeating: 0, count: Self.maxPathLength)
        return allPIDs().compactMap { pid in
            guard let path = executablePath(of: pid, buffer: &buffer), let source = Self.source(forExecutablePath: path) else { return nil }
            let sockets = tcpSockets(of: pid).map(RemoteProcessSnapshot.Sockets.inspected) ?? .unavailable
            return RemoteProcessSnapshot(source: source, pid: pid, sockets: sockets)
        }
    }

    /// Maps an executable path to the remote-access product it belongs to.
    static func source(forExecutablePath path: String) -> RemoteSessionSource? {
        let name = (path as NSString).lastPathComponent
        if path.localizedCaseInsensitiveContains("/AnyDesk.app/") || name.caseInsensitiveCompare("AnyDesk") == .orderedSame {
            return .anyDesk
        }
        if name == "screensharingd" { return .screenSharing }
        if name == "ARDAgent" { return .remoteManagement }
        return nil
    }

    // MARK: - libproc

    private func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + Self.pidHeadroom)
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count))).filter { $0 > 0 }
    }

    private func executablePath(of pid: pid_t, buffer: inout [CChar]) -> String? {
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func tcpSockets(of pid: pid_t) -> [RemoteTCPSocket]? {
        let stride = MemoryLayout<proc_fdinfo>.stride
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return nil }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride + Self.fdHeadroom)
        let filled = fds.withUnsafeMutableBytes { buffer in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard filled > 0 else { return nil }
        return fds.prefix(Int(filled) / stride)
            .filter { $0.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) }
            .compactMap { socket(pid: pid, fd: $0.proc_fd) }
    }

    private func socket(pid: pid_t, fd: Int32) -> RemoteTCPSocket? {
        var info = socket_fdinfo()
        let expected = Int32(MemoryLayout<socket_fdinfo>.size)
        guard proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, &info, expected) == expected,
              info.psi.soi_kind == SOCKINFO_TCP
        else { return nil }
        let tcp = info.psi.soi_proto.pri_tcp
        let inet = tcp.tcpsi_ini
        return RemoteTCPSocket(
            state: Self.state(tcp.tcpsi_state),
            localPort: UInt16(bigEndian: UInt16(truncatingIfNeeded: inet.insi_lport)),
            remotePort: UInt16(bigEndian: UInt16(truncatingIfNeeded: inet.insi_fport)),
            remoteAddress: Self.remoteAddress(inet)
        )
    }

    private static func state(_ raw: Int32) -> RemoteTCPState {
        switch raw {
        case TSI_S_ESTABLISHED: .established
        case TSI_S_LISTEN: .listening
        default: .other
        }
    }

    private static func remoteAddress(_ inet: in_sockinfo) -> RemoteSocketAddress {
        if inet.insi_vflag & UInt8(INI_IPV4) != 0 {
            var address = inet.insi_faddr.ina_46.i46a_addr4
            return .ipv4(withUnsafeBytes(of: &address) { Array($0) })
        }
        var address = inet.insi_faddr.ina_6
        return .ipv6(withUnsafeBytes(of: &address) { Array($0) })
    }
}
