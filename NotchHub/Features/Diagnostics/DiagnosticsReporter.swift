import AppKit
import Foundation
import OSLog

/// Opens URLs in the default browser; faked in tests.
@MainActor
protocol DiagnosticsURLOpening: AnyObject {
    func open(_ url: URL)
}

@MainActor
final class WorkspaceDiagnosticsURLOpener: DiagnosticsURLOpening {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

/// "Sorun bildir…": collects a redacted report, copies it and opens a prefilled GitHub issue.
@MainActor
final class DiagnosticsReporter {
    static let logWindow: TimeInterval = 60 * 60

    struct Dependencies {
        var snapshotFacts: @MainActor () -> (app: String, build: String, os: String, model: String, displays: [DiagnosticsDisplay])
        var issueURLSetting: @MainActor () -> String?
        var homeDirectory: String
        var now: @MainActor () -> Date

        static let live = Dependencies(
            snapshotFacts: {
                (
                    DiagnosticsSystemInfo.appVersion,
                    DiagnosticsSystemInfo.appBuild,
                    DiagnosticsSystemInfo.osVersion,
                    DiagnosticsSystemInfo.modelIdentifier,
                    DiagnosticsSystemInfo.displays
                )
            },
            issueURLSetting: { DiagnosticsSystemInfo.issueURLSetting },
            homeDirectory: NSHomeDirectory(),
            now: { Date() }
        )
    }

    private let settings: SettingsStore
    private let permissions: PermissionsModel
    private let alerts: NotchAlertCenter
    private let pasteboard: any InsightsPasteboard
    private let urlOpener: any DiagnosticsURLOpening
    private let logReader: any DiagnosticsLogReading
    private let environment: Dependencies
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Diagnostics")
    private(set) var isBusy = false

    init(
        settings: SettingsStore,
        permissions: PermissionsModel,
        alerts: NotchAlertCenter,
        pasteboard: any InsightsPasteboard = SystemInsightsPasteboard(),
        urlOpener: any DiagnosticsURLOpening = WorkspaceDiagnosticsURLOpener(),
        logReader: any DiagnosticsLogReading = OSLogDiagnosticsReader(),
        dependencies: Dependencies = .live
    ) {
        self.settings = settings
        self.permissions = permissions
        self.alerts = alerts
        self.pasteboard = pasteboard
        self.urlOpener = urlOpener
        self.logReader = logReader
        self.environment = dependencies
    }

    /// Copies the full report; opens the issue page when `NHIssueURL` is configured, otherwise toasts.
    func report() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        logger.info("Building diagnostics report")
        let snapshot = await makeSnapshot()
        let home = environment.homeDirectory
        let fullReport = DiagnosticsRedactor.redact(DiagnosticsReportFormatter.fullReport(snapshot), homeDirectory: home)
        let summary = DiagnosticsRedactor.redact(DiagnosticsReportFormatter.summary(snapshot), homeDirectory: home)
        pasteboard.copy(fullReport)

        guard let base = DiagnosticsIssueURL.baseURL(from: environment.issueURLSetting()),
              let issueURL = DiagnosticsIssueURL.make(base: base, summary: summary)
        else {
            logger.info("No issue URL configured; report copied only")
            postToast(subtitle: "Raporu e-postana ya da bir sorun kaydına yapıştırabilirsin.")
            return
        }
        urlOpener.open(issueURL)
        postToast(subtitle: "Açılan sayfaya yapıştır (⌘V).")
    }

    func makeSnapshot() async -> DiagnosticsSnapshot {
        await permissions.refresh()
        let facts = environment.snapshotFacts()
        let now = environment.now()
        return DiagnosticsSnapshot(
            appVersion: facts.app,
            appBuild: facts.build,
            osVersion: facts.os,
            modelIdentifier: facts.model,
            displays: facts.displays,
            enabledModules: NotchModule.allCases.filter(settings.isEnabled).map(\.rawValue),
            permissions: permissions.allStatuses.map {
                DiagnosticsPermissionLine(name: $0.permission.rawValue, status: $0.status.reportLabel)
            },
            logLines: await readLogs(since: now.addingTimeInterval(-Self.logWindow)),
            generatedAt: now
        )
    }

    private func readLogs(since date: Date) async -> [String] {
        do {
            return try await logReader.recentLines(since: date, limit: DiagnosticsReportFormatter.maxLogLines)
        } catch {
            logger.error("Reading log store failed: \(error.localizedDescription, privacy: .public)")
            return ["(log unavailable: \(error.localizedDescription))"]
        }
    }

    private func postToast(subtitle: String) {
        alerts.post(NotchAlert(
            module: nil,
            systemImage: "doc.on.clipboard",
            title: "Tanılama raporu kopyalandı",
            subtitle: subtitle,
            style: .success
        ))
    }
}
