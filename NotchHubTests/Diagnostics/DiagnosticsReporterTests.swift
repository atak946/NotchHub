import Foundation
import Testing
@testable import NotchHub

@MainActor
final class RecordingPasteboard: InsightsPasteboard {
    private(set) var copied: [String] = []
    func copy(_ text: String) { copied.append(text) }
}

@MainActor
final class RecordingURLOpener: DiagnosticsURLOpening {
    private(set) var opened: [URL] = []
    func open(_ url: URL) { opened.append(url) }
}

struct StubLogReader: DiagnosticsLogReading {
    var lines: [String] = []
    var error: (any Error)?

    func recentLines(since date: Date, limit: Int) async throws -> [String] {
        if let error { throw error }
        return Array(lines.suffix(limit))
    }
}

struct StubLogError: Error {}

@MainActor
struct DiagnosticsReporterTests {
    private static let home = "/Users/sample"

    private func makeReporter(
        issueSetting: String?,
        logs: StubLogReader = StubLogReader(lines: ["10:00:00.000 [info] [App] opened /Users/sample/a.txt for a@b.com"])
    ) -> (DiagnosticsReporter, RecordingPasteboard, RecordingURLOpener, NotchAlertCenter) {
        let suite = "DiagnosticsReporterTests.\(UUID().uuidString)"
        let settings = SettingsStore(defaults: UserDefaults(suiteName: suite) ?? .standard)
        let checker = FakePermissionChecker()
        checker.statuses = [.calendar: .granted, .automation: .denied]
        let permissions = PermissionsModel(checker: checker, clock: CountingPollingClock(allowedSleeps: 0))
        let alerts = NotchAlertCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        let pasteboard = RecordingPasteboard()
        let opener = RecordingURLOpener()
        let dependencies = DiagnosticsReporter.Dependencies(
            snapshotFacts: {
                ("1.4.0", "6", "Version 26.1", "Mac15,6", [DiagnosticsDisplay(isBuiltIn: true, hasNotch: true, width: 1512, height: 982)])
            },
            issueURLSetting: { issueSetting },
            homeDirectory: Self.home,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let reporter = DiagnosticsReporter(
            settings: settings,
            permissions: permissions,
            alerts: alerts,
            pasteboard: pasteboard,
            urlOpener: opener,
            logReader: logs,
            dependencies: dependencies
        )
        return (reporter, pasteboard, opener, alerts)
    }

    @Test func withoutIssueURLOnlyCopiesAndToasts() async throws {
        let (reporter, pasteboard, opener, alerts) = makeReporter(issueSetting: "")

        await reporter.report()

        let report = try #require(pasteboard.copied.first)
        #expect(opener.opened.isEmpty)
        #expect(alerts.current?.title == "Tanılama raporu kopyalandı")
        #expect(report.contains("NotchHub 1.4.0 (6)"))
        #expect(report.contains("Mac: Mac15,6"))
        #expect(report.contains("Display 1: 1512x982, built-in, notch"))
        #expect(report.contains("calendar: granted"))
        #expect(report.contains("automation: denied"))
        #expect(report.contains("opened ~/a.txt for <email>"))
        #expect(!report.contains("/Users/sample"))
    }

    @Test func withIssueURLOpensPrefilledSummary() async throws {
        let (reporter, pasteboard, opener, _) = makeReporter(issueSetting: "owner/repo")

        await reporter.report()

        let url = try #require(opener.opened.first)
        #expect(pasteboard.copied.count == 1)
        #expect(url.absoluteString.hasPrefix("https://github.com/owner/repo/issues/new?"))
        #expect(url.absoluteString.utf8.count <= DiagnosticsIssueURL.maxLength)
        // The URL carries the summary only, never the log lines.
        #expect(!url.absoluteString.contains("opened"))
    }

    @Test func logFailureIsReportedInline() async throws {
        let (reporter, pasteboard, _, _) = makeReporter(issueSetting: nil, logs: StubLogReader(error: StubLogError()))

        await reporter.report()

        let report = try #require(pasteboard.copied.first)
        #expect(report.contains("(log unavailable"))
    }

    @Test func formatterCapsLogLinesAndNotesEmptyLogs() {
        let snapshot = DiagnosticsSnapshot(
            appVersion: "1", appBuild: "1", osVersion: "x", modelIdentifier: "m",
            displays: [], enabledModules: [], permissions: [],
            logLines: (1...250).map { "l\($0)" },
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let report = DiagnosticsReportFormatter.fullReport(snapshot)
        #expect(report.contains("200 lines"))
        #expect(!report.contains("\nl50\n"))
        #expect(report.hasSuffix("l250"))
        #expect(report.contains("Modules: none"))

        let empty = DiagnosticsSnapshot(
            appVersion: "1", appBuild: "1", osVersion: "x", modelIdentifier: "m",
            displays: [], enabledModules: [], permissions: [], logLines: [],
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(DiagnosticsReportFormatter.fullReport(empty).hasSuffix(DiagnosticsReportFormatter.noLogsLine))
    }
}
