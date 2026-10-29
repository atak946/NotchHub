import Foundation

/// Finds `code` and `docker` without relying on the (minimal) GUI-app PATH.
struct ProfilesCLIResolver: Sendable {
    static let vscodeCLIRelativePath = "Contents/Resources/app/bin/code"
    static let defaultVSCodeBundlePaths = ["/Applications/Visual Studio Code.app"]
    /// Directories that hold CLI tools on typical developer Macs, in lookup order.
    static let standardToolDirectories = ["/usr/local/bin", "/opt/homebrew/bin"]
    static let systemPath = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    let fileSystem: any ProfilesFileSystem
    let homeDirectory: String
    /// Value of `PATH` from the environment (often only the system directories for GUI apps).
    let environmentPath: String?
    /// Bundle paths of VS Code as reported by Launch Services, if any.
    let vscodeBundlePaths: [String]

    init(
        fileSystem: any ProfilesFileSystem = LiveProfilesFileSystem(),
        homeDirectory: String = NSHomeDirectory(),
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
        vscodeBundlePaths: [String] = ProfilesCLIResolver.defaultVSCodeBundlePaths
    ) {
        self.fileSystem = fileSystem
        self.homeDirectory = homeDirectory
        self.environmentPath = environmentPath
        self.vscodeBundlePaths = vscodeBundlePaths
    }

    func codeCandidates() -> [String] {
        let bundles = vscodeBundlePaths + [(homeDirectory as NSString).appendingPathComponent("Applications/Visual Studio Code.app")]
        return deduplicated(
            Self.standardToolDirectories.map { "\($0)/code" }
                + bundles.map { ($0 as NSString).appendingPathComponent(Self.vscodeCLIRelativePath) }
        )
    }

    func dockerCandidates() -> [String] {
        let pathEntries = (environmentPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        let directories = Self.standardToolDirectories
            + [(homeDirectory as NSString).appendingPathComponent(".orbstack/bin"),
               (homeDirectory as NSString).appendingPathComponent(".docker/bin"),
               "/Applications/Docker.app/Contents/Resources/bin",
               "/Applications/OrbStack.app/Contents/MacOS/xbin"]
            + pathEntries
        return deduplicated(directories.map { "\($0)/docker" })
    }

    func resolveCode() -> URL? {
        firstExecutable(in: codeCandidates())
    }

    func resolveDocker() -> URL? {
        firstExecutable(in: dockerCandidates())
    }

    /// PATH for child processes: tool directories first so helpers (credential stores, compose plugins) resolve.
    func childProcessPath(including executable: URL?) -> String {
        let executableDirectory = executable.map { $0.deletingLastPathComponent().path(percentEncoded: false) }
        let entries = [executableDirectory].compactMap { $0 }
            + Self.standardToolDirectories
            + [(homeDirectory as NSString).appendingPathComponent(".orbstack/bin")]
            + Self.systemPath
        return deduplicated(entries.map { $0.hasSuffix("/") && $0.count > 1 ? String($0.dropLast()) : $0 })
            .joined(separator: ":")
    }

    private func firstExecutable(in candidates: [String]) -> URL? {
        candidates.first { fileSystem.isExecutableFile(atPath: $0) }.map { URL(filePath: $0) }
    }

    private func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
