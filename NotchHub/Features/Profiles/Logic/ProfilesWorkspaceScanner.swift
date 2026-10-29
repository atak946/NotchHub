import Foundation

enum ProfilesProjectKind: String, CaseIterable, Comparable, Sendable {
    case compose
    case dotnet
    case node

    var title: String {
        switch self {
        case .compose: "Compose"
        case .dotnet: ".NET"
        case .node: "Node"
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
    }
}

/// A folder under the workspace root that looks like a project and could become a profile.
struct ProfilesWorkspaceSuggestion: Identifiable, Hashable, Sendable {
    let path: String
    let kinds: Set<ProfilesProjectKind>

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var sortedKinds: [ProfilesProjectKind] { kinds.sorted() }

    /// Template profile: VS Code + terminal, plus compose up/stop when a compose file exists.
    func makeProfile(color: ProfileColor = .blue) -> ClientProfile {
        var steps: [ProfileStep] = []
        if kinds.contains(.compose) {
            steps.append(ProfileStep(action: .dockerComposeUp(path: path)))
        }
        steps.append(ProfileStep(action: .openInVSCode(path: path)))
        steps.append(ProfileStep(action: .openTerminal(path: path), continueOnFailure: true))
        let deactivate = kinds.contains(.compose) ? [ProfileStep(action: .dockerComposeStop(path: path))] : []
        return ClientProfile(name: name, color: color, steps: steps, deactivateSteps: deactivate)
    }
}

/// Scans a workspace root (depth 2) for project folders. Pure over `ProfilesFileSystem`, safe off the main actor.
struct ProfilesWorkspaceScanner: Sendable {
    static let maxDepth = 2
    static let maxSuggestions = 200
    static let ignoredFolderNames: Set<String> = [
        "node_modules", "bin", "obj", "build", "dist", "out", "vendor", "Pods", "DerivedData",
    ]

    let fileSystem: any ProfilesFileSystem

    init(fileSystem: any ProfilesFileSystem = LiveProfilesFileSystem()) {
        self.fileSystem = fileSystem
    }

    func scan(root: String) -> [ProfilesWorkspaceSuggestion] {
        guard fileSystem.itemKind(atPath: root) == .directory else { return [] }
        var results: [ProfilesWorkspaceSuggestion] = []
        visit(folder: root, depth: 0, into: &results)
        return Array(results.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .prefix(Self.maxSuggestions))
    }

    /// Project kinds detected from the entry names of one folder.
    static func classify(entries: [String]) -> Set<ProfilesProjectKind> {
        var kinds: Set<ProfilesProjectKind> = []
        let lowered = Set(entries.map { $0.lowercased() })
        if ProfileStepValidator.composeFileNames.contains(where: lowered.contains) {
            kinds.insert(.compose)
        }
        if lowered.contains(where: { $0.hasSuffix(".sln") || $0.hasSuffix(".slnx") }) {
            kinds.insert(.dotnet)
        }
        if lowered.contains("package.json") {
            kinds.insert(.node)
        }
        return kinds
    }

    private func visit(folder: String, depth: Int, into results: inout [ProfilesWorkspaceSuggestion]) {
        let entries = fileSystem.contentsOfDirectory(atPath: folder)
        if depth > 0 {
            let fileEntries = entries.filter { fileSystem.itemKind(atPath: join(folder, $0)) == .file }
            let kinds = Self.classify(entries: fileEntries)
            if !kinds.isEmpty {
                results.append(ProfilesWorkspaceSuggestion(path: folder, kinds: kinds))
            }
        }
        guard depth < Self.maxDepth else { return }
        for name in entries where isScannable(name) {
            let child = join(folder, name)
            guard fileSystem.itemKind(atPath: child) == .directory else { continue }
            visit(folder: child, depth: depth + 1, into: &results)
        }
    }

    private func isScannable(_ name: String) -> Bool {
        !name.hasPrefix(".") && !Self.ignoredFolderNames.contains(name) && !name.hasSuffix(".app")
    }

    private func join(_ folder: String, _ name: String) -> String {
        (folder as NSString).appendingPathComponent(name)
    }
}
