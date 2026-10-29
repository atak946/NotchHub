import Foundation
import Testing
@testable import NotchHub

struct ProfilesWorkspaceScannerTests {
    /// Builds a real temporary tree and returns its root path.
    private func makeTree(_ files: [String]) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfilesScan-\(UUID().uuidString)", isDirectory: true)
        for relative in files {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("EmptyClient"), withIntermediateDirectories: true)
        return root.path(percentEncoded: false).replacingOccurrences(of: "/$", with: "", options: .regularExpression)
    }

    @Test func classifiesFoldersUpToDepthTwo() throws {
        let root = try makeTree([
            "Acme/docker-compose.yml",
            "Acme/Acme.sln",
            "Globex/web/package.json",
            "Globex/api/Globex.Api.slnx",
            "Initech/compose.yaml",
            "Deep/a/b/package.json",
            "Vue/node_modules/lib/package.json",
            ".hidden/package.json",
            "README.md",
        ])
        defer { try? FileManager.default.removeItem(atPath: root) }

        let results = ProfilesWorkspaceScanner().scan(root: root)
        let byName = Dictionary(uniqueKeysWithValues: results.map { ($0.path.replacingOccurrences(of: root + "/", with: ""), $0.kinds) })

        #expect(byName["Acme"] == [.compose, .dotnet])
        #expect(byName["Globex/web"] == [.node])
        #expect(byName["Globex/api"] == [.dotnet])
        #expect(byName["Initech"] == [.compose])
        #expect(byName["Deep/a/b"] == nil)
        #expect(byName["Vue/node_modules"] == nil)
        #expect(byName.keys.contains { $0.hasPrefix(".hidden") } == false)
        #expect(byName["EmptyClient"] == nil)
        #expect(results.count == 4)
    }

    @Test func missingRootYieldsNothing() {
        #expect(ProfilesWorkspaceScanner().scan(root: "/definitely/not/here-\(UUID().uuidString)").isEmpty)
    }

    @Test func classifyIsCaseInsensitiveForComposeAndPackage() {
        #expect(ProfilesWorkspaceScanner.classify(entries: ["Docker-Compose.YML", "Package.json"]) == [.compose, .node])
        #expect(ProfilesWorkspaceScanner.classify(entries: ["README.md", "src"]).isEmpty)
    }

    @Test func suggestionWithoutComposeHasNoDeactivateSteps() {
        let profile = ProfilesWorkspaceSuggestion(path: "/w/web", kinds: [.node]).makeProfile()
        #expect(profile.steps.map(\.action.kind) == [.openInVSCode, .openTerminal])
        #expect(profile.deactivateSteps.isEmpty)
    }
}
