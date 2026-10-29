import Foundation
import Testing
@testable import NotchHub

struct ProfilesCLIResolverTests {
    private func resolver(_ executables: Set<String>, path: String? = "/usr/bin:/bin") -> ProfilesCLIResolver {
        ProfilesCLIResolver(
            fileSystem: ProfilesFakeFileSystem(executables: executables),
            homeDirectory: "/Users/test",
            environmentPath: path,
            vscodeBundlePaths: ["/Applications/Visual Studio Code.app"]
        )
    }

    @Test func prefersUsrLocalCode() {
        let found = resolver(["/usr/local/bin/code", "/opt/homebrew/bin/code"]).resolveCode()
        #expect(found?.path() == "/usr/local/bin/code")
    }

    @Test func fallsBackToHomebrewThenBundleCLI() {
        #expect(resolver(["/opt/homebrew/bin/code"]).resolveCode()?.path() == "/opt/homebrew/bin/code")
        let bundled = "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
        #expect(resolver([bundled]).resolveCode()?.path(percentEncoded: false) == bundled)
        let userBundled = "/Users/test/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
        #expect(resolver([userBundled]).resolveCode()?.path(percentEncoded: false) == userBundled)
    }

    @Test func noCodeCLIReturnsNil() {
        #expect(resolver([]).resolveCode() == nil)
    }

    @Test func findsDockerInOrbStackHome() {
        #expect(resolver(["/Users/test/.orbstack/bin/docker"]).resolveDocker()?.path() == "/Users/test/.orbstack/bin/docker")
    }

    @Test func dockerStandardDirectoriesWinOverPATH() {
        let found = resolver(["/custom/bin/docker", "/usr/local/bin/docker"], path: "/custom/bin").resolveDocker()
        #expect(found?.path() == "/usr/local/bin/docker")
    }

    @Test func dockerFromPATHAsLastResort() {
        #expect(resolver(["/custom/bin/docker"], path: "/custom/bin:relative/bin").resolveDocker()?.path() == "/custom/bin/docker")
        #expect(!resolver([]).dockerCandidates().contains("relative/bin/docker"))
    }

    @Test func childPathStartsWithToolDirectory() {
        let path = resolver([]).childProcessPath(including: URL(filePath: "/Users/test/.orbstack/bin/docker"))
        let entries = path.split(separator: ":").map(String.init)
        #expect(entries.first == "/Users/test/.orbstack/bin")
        #expect(entries.contains("/usr/bin"))
        #expect(Set(entries).count == entries.count)
    }
}
