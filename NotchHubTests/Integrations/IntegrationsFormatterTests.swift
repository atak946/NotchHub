import Foundation
import Testing
@testable import NotchHub

struct IntegrationsDurationFormatterTests {
    @Test(arguments: [
        (0.2, "<1sn"), (1, "1sn"), (45.9, "45sn"), (60, "1dk"), (72, "1dk 12sn"), (599, "9dk 59sn"),
        (3600, "1sa"), (3725, "1sa 2dk"), (90_000, "25sa"), (-5, "<1sn"), (.infinity, "<1sn"), (.nan, "<1sn"),
    ] as [(TimeInterval, String)])
    func formats(elapsed: TimeInterval, expected: String) {
        #expect(IntegrationsDurationFormatter.text(for: elapsed) == expected)
    }
}

struct IntegrationsCommandFormatterTests {
    @Test(arguments: [
        ("dotnet build", "dotnet build"),
        ("dotnet build -c Release", "dotnet build"),
        ("npm test", "npm test"),
        ("npm run build -- --prod", "npm run build"),
        ("pnpm exec vitest run", "pnpm exec vitest"),
        ("FOO=1 BAR=baz make all", "make all"),
        ("sudo -E /usr/local/bin/brew upgrade", "brew upgrade"),
        ("time env CI=1 swift test", "swift test"),
        ("xcodebuild -scheme NotchHub test", "xcodebuild"),
        ("./scripts/deploy.sh production", "deploy.sh production"),
        ("cargo build && cargo test", "cargo build"),
        ("make|tee log.txt", "make"),
        ("git push; say done", "git push"),
        ("docker compose up --build", "docker compose"),
        ("'my tool' --flag", "my tool"),
        ("python3 train.py", "python3"),
        ("", "Komut"),
        ("FOO=1", "Komut"),
        ("   ", "Komut"),
    ])
    func extractsCommandName(commandLine: String, expected: String) {
        #expect(CommandFinishedFormatter.commandName(from: commandLine) == expected)
    }

    @Test func longNamesAreTruncated() {
        let name = CommandFinishedFormatter.commandName(from: String(repeating: "x", count: 100))
        #expect(name.count == CommandFinishedFormatter.maxNameLength)
    }

    @Test func controlCharactersNeverReachTheName() {
        let name = CommandFinishedFormatter.commandName(from: "ev\u{202E}il\u{0007} build")
        #expect(name == "evil build")
    }

    @Test func successAndFailureTitles() {
        #expect(CommandFinishedFormatter.title(for: .init(commandLine: "dotnet build", exitCode: 0, elapsed: 72))
            == "✓ dotnet build · 1dk 12sn")
        #expect(CommandFinishedFormatter.title(for: .init(commandLine: "npm test", exitCode: 1, elapsed: 45))
            == "✗ npm test başarısız (çıkış 1) · 45sn")
    }

    @Test func styleAndSymbolFollowExitCode() {
        let ok = ExternalCommandResult(commandLine: "x", exitCode: 0, elapsed: 1)
        let bad = ExternalCommandResult(commandLine: "x", exitCode: 2, elapsed: 1)
        #expect(CommandFinishedFormatter.style(for: ok) == .success)
        #expect(CommandFinishedFormatter.style(for: bad) == .urgent)
        #expect(CommandFinishedFormatter.systemImage(for: ok) == CommandFinishedFormatter.successSymbol)
        #expect(CommandFinishedFormatter.systemImage(for: bad) == CommandFinishedFormatter.failureSymbol)
    }
}
