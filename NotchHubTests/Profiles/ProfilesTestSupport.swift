import Foundation
import Synchronization
@testable import NotchHub

/// In-memory file system: register directories, files and executables by absolute path.
struct ProfilesFakeFileSystem: ProfilesFileSystem {
    var directories: Set<String> = []
    var files: Set<String> = []
    var executables: Set<String> = []

    func itemKind(atPath path: String) -> ProfilesItemKind {
        if directories.contains(path) { return .directory }
        if files.contains(path) || executables.contains(path) { return .file }
        return .missing
    }

    func isExecutableFile(atPath path: String) -> Bool {
        executables.contains(path)
    }

    func contentsOfDirectory(atPath path: String) -> [String] {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        let children = (directories.union(files).union(executables))
            .filter { $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("/") && $0.count > prefix.count }
            .map { String($0.dropFirst(prefix.count)) }
        return children.sorted()
    }
}

/// Scripted executor: records executed actions; per-action behavior via `behavior`.
@MainActor
final class ProfilesFakeExecutor: ProfileStepExecuting {
    enum Behavior {
        case succeed(String?)
        case fail(String)
        /// Suspends until the task is cancelled.
        case hang
        case prompt(ProfilePrompt)
    }

    var behavior: (ProfileAction) -> Behavior = { _ in .succeed(nil) }
    private(set) var executed: [ProfileAction] = []
    private(set) var hangStarted = false

    func execute(_ action: ProfileAction, prompt: @escaping @MainActor (ProfilePrompt) -> Void) async throws -> String? {
        executed.append(action)
        switch behavior(action) {
        case let .succeed(detail):
            return detail
        case let .fail(message):
            throw ProfileStepFailure(message: message)
        case .hang:
            hangStarted = true
            try await Task.sleep(for: .seconds(3600))
            return nil
        case let .prompt(value):
            prompt(value)
            return "prompted"
        }
    }
}

/// Validator that accepts every action (paths in runner tests don't exist on disk).
func makeProfilesPermissiveValidator() -> ProfileStepValidator {
    ProfileStepValidator(fileSystem: ProfilesPermissiveFileSystem())
}

struct ProfilesPermissiveFileSystem: ProfilesFileSystem {
    func itemKind(atPath path: String) -> ProfilesItemKind {
        ProfileStepValidator.composeFileNames.contains((path as NSString).lastPathComponent) ? .file : .directory
    }

    func isExecutableFile(atPath path: String) -> Bool { true }
    func contentsOfDirectory(atPath path: String) -> [String] { [] }
}

final class ProfilesFakeProbe: RemoteSessionProbing {
    private let storage = Mutex<[RemoteProcessSnapshot]>([])

    func set(_ snapshots: [RemoteProcessSnapshot]) {
        storage.withLock { $0 = snapshots }
    }

    func snapshots() -> [RemoteProcessSnapshot] {
        storage.withLock { $0 }
    }
}

func makeProfilesTestDefaults() -> UserDefaults {
    let suiteName = "NotchHubTests.Profiles.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// Alert center whose auto-dismiss never fires, so tests can inspect `current`.
@MainActor
func makeProfilesTestAlerts() -> NotchAlertCenter {
    NotchAlertCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
}

@MainActor
func profilesWaitUntil(_ condition: @MainActor () -> Bool, maxYields: Int = 10_000) async {
    for _ in 0..<maxYields where !condition() {
        await Task.yield()
    }
}

func profilesTCP(
    _ state: RemoteTCPState = .established,
    local: UInt16 = 50_000,
    remote: UInt16 = 443,
    address: RemoteSocketAddress = .ipv4([93, 184, 216, 34])
) -> RemoteTCPSocket {
    RemoteTCPSocket(state: state, localPort: local, remotePort: remote, remoteAddress: address)
}
