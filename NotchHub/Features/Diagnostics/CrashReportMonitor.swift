import AppKit
import Foundation
import OSLog

/// Shows a file in Finder; faked in tests.
@MainActor
protocol CrashReportFileRevealing: AnyObject {
    func reveal(_ file: URL)
}

@MainActor
final class WorkspaceCrashReportRevealer: CrashReportFileRevealing {
    func reveal(_ file: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }
}

/// After a crash, offers to file a sanitized GitHub issue built from the system's `.ips` report.
/// Nothing leaves the Mac unless the user presses "Bildir" and submits the page themselves.
@MainActor
final class CrashReportMonitor {
    static let promptCoalescingKey = "crash-report-prompt"

    struct Dependencies {
        var now: @MainActor () -> Date
        var issueURLSetting: @MainActor () -> String?
        var homeDirectory: String

        static let live = Dependencies(
            now: { Date() },
            issueURLSetting: { DiagnosticsSystemInfo.issueURLSetting },
            homeDirectory: NSHomeDirectory()
        )
    }

    private let ledger: CrashReportLedger
    private let locator: CrashReportLocator
    private let alerts: NotchAlertCenter
    private let urlOpener: any DiagnosticsURLOpening
    private let revealer: any CrashReportFileRevealing
    private let pasteboard: any InsightsPasteboard
    private let environment: Dependencies
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "CrashReports")
    private var powerOffObserver: (any NSObjectProtocol)?

    init(
        alerts: NotchAlertCenter,
        ledger: CrashReportLedger = CrashReportLedger(),
        locator: CrashReportLocator = CrashReportLocator(
            directories: CrashReportLocator.liveDirectories,
            processName: ProcessInfo.processInfo.processName,
            lister: FileManagerCrashReportLister()
        ),
        urlOpener: any DiagnosticsURLOpening = WorkspaceDiagnosticsURLOpener(),
        revealer: any CrashReportFileRevealing = WorkspaceCrashReportRevealer(),
        pasteboard: any InsightsPasteboard = SystemInsightsPasteboard(),
        dependencies: Dependencies = .live
    ) {
        self.alerts = alerts
        self.ledger = ledger
        self.locator = locator
        self.urlOpener = urlOpener
        self.revealer = revealer
        self.pasteboard = pasteboard
        self.environment = dependencies
    }

    /// Call once at launch. Returns the report it prompted for, if any.
    @discardableResult
    func checkOnLaunch() -> CrashReportFile? {
        let previousLaunch = ledger.lastLaunch
        let wasRunning = ledger.wasRunning
        ledger.recordLaunch(at: environment.now())
        observePowerOff()

        guard ledger.isPromptEnabled else { return nil }
        guard let file = locator.newestUnhandled(since: previousLaunch, handled: ledger.handledNames) else {
            // A sentinel without a report is a forced quit, logout or power loss: never prompt.
            if wasRunning { logger.info("Previous run ended uncleanly without a crash report") }
            return nil
        }
        ledger.markHandled(file.name)
        guard let report = parse(file) else { return nil }
        logger.info("Previous run crashed; offering a report")
        alerts.post(prompt(for: report, file: file))
        return file
    }

    /// Call from `applicationWillTerminate`.
    func recordCleanExit() {
        ledger.recordCleanExit()
    }

    func parse(_ file: CrashReportFile) -> CrashReport? {
        do {
            return try CrashReportParser.parse(locator.lister.contents(of: file.url))
        } catch {
            logger.error("Could not read crash report: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func prompt(for report: CrashReport, file: CrashReportFile) -> NotchAlert {
        NotchAlert(
            module: nil,
            systemImage: "exclamationmark.triangle.fill",
            title: String(localized: "NotchHub beklenmedik şekilde kapandı"),
            subtitle: String(localized: "Gizliliği koruyan bir çökme raporu göndermek ister misin?"),
            style: .urgent,
            coalescingKey: Self.promptCoalescingKey,
            autoDismissAfter: NotchAlert.importantDuration,
            actionTitle: String(localized: "Bildir"),
            action: { [weak self] in self?.report(report, file: file) },
            secondaryActionTitle: String(localized: "Yoksay"),
            secondaryAction: {}
        )
    }

    /// "Bildir": opens the prefilled issue (or copies the summary) and offers the full file in Finder.
    func report(_ report: CrashReport, file: CrashReportFile) {
        let summary = CrashReportFormatter.summary(report, homeDirectory: environment.homeDirectory)
        let title = CrashReportFormatter.issueTitle + report.exceptionType
        let instruction = CrashReportFormatter.attachInstruction
        if let base = DiagnosticsIssueURL.baseURL(from: environment.issueURLSetting()),
           let url = DiagnosticsIssueURL.make(base: base, title: title, summary: summary, instruction: instruction) {
            urlOpener.open(url)
        } else {
            logger.info("No issue URL configured; crash summary copied only")
            pasteboard.copy(DiagnosticsIssueURL.body(summary: summary, instruction: instruction))
        }
        alerts.post(NotchAlert(
            module: nil,
            systemImage: "doc.text.magnifyingglass",
            title: String(localized: "Çökme raporu hazır"),
            subtitle: String(localized: "Tam raporu eklemek için dosyayı sayfaya sürükleyebilirsin."),
            style: .info,
            autoDismissAfter: NotchAlert.importantDuration,
            actionTitle: String(localized: "Raporu Finder'da göster"),
            action: { [weak self] in self?.revealer.reveal(file.url) }
        ))
    }

    /// Logout, restart and shutdown terminate the app; count them as clean exits.
    private func observePowerOff() {
        guard powerOffObserver == nil else { return }
        powerOffObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordCleanExit() }
        }
    }
}
