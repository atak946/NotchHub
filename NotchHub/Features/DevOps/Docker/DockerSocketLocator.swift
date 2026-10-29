import Darwin
import Foundation

/// File-system queries needed to locate the Docker socket, injectable for tests.
protocol DevOpsFileSystem: Sendable {
    var homeDirectoryPath: String { get }
    /// `true` when `path` (following symlinks) is a Unix domain socket.
    func isSocket(atPath path: String) -> Bool
}

struct LocalDevOpsFileSystem: DevOpsFileSystem {
    var homeDirectoryPath: String { NSHomeDirectory() }

    func isSocket(atPath path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFSOCK
    }
}

/// Finds the first live Docker-compatible socket: OrbStack, Docker default, Docker Desktop, colima.
enum DockerSocketLocator {
    static func candidatePaths(home: String) -> [String] {
        let base = home.hasSuffix("/") ? String(home.dropLast()) : home
        return [
            "\(base)/.orbstack/run/docker.sock",
            "/var/run/docker.sock",
            "\(base)/.docker/run/docker.sock",
            "\(base)/.colima/default/docker.sock",
        ]
    }

    static func resolve(fileSystem: any DevOpsFileSystem) -> String? {
        candidatePaths(home: fileSystem.homeDirectoryPath).first { fileSystem.isSocket(atPath: $0) }
    }
}
