import Foundation
import Testing
@testable import NotchHub

struct CrashReportParserTests {
    @Test func parsesHeaderExceptionAndCrashedThread() throws {
        let report = try CrashReportParser.parse(CrashReportFixture.ips)
        #expect(report.appVersion == "1.3.2")
        #expect(report.appBuild == "5")
        #expect(report.osVersion == "macOS 26.6.2 (25G83)")
        #expect(report.cpuType == "ARM-64")
        #expect(report.exceptionType == "EXC_BREAKPOINT")
        #expect(report.exceptionSignal == "SIGTRAP")
        #expect(report.exceptionCodes == "0x0000000000000001, 0x00000001a07f1510")
        #expect(report.crashedThread == 1)
    }

    @Test func keepsOnlyTopFramesOfTheCrashedThreadWithImageBasenames() throws {
        let report = try CrashReportParser.parse(CrashReportFixture.ips)
        #expect(report.frames.count == CrashReportParser.maxFrames)
        #expect(report.frames[0] == .init(
            image: "libswiftCore.dylib",
            symbol: "closure #1 in _assertionFailure(_:_:file:line:flags:)",
            offset: 400
        ))
        #expect(report.frames[2] == .init(image: "NotchHub", symbol: nil, offset: 4096))
        #expect(!report.frames.contains { $0.symbol == CrashReportFixture.otherThreadSymbol })
    }

    @Test func rejectsMalformedInput() {
        #expect(throws: CrashReportParseError.missingHeader) { try CrashReportParser.parse("{}") }
        #expect(throws: CrashReportParseError.invalidJSON) { try CrashReportParser.parse("{}\nnot json") }
        #expect(throws: CrashReportParseError.notACrash) { try CrashReportParser.parse("{}\n{\"threads\":[]}") }
    }

    @Test func basenameStripsDirectories() {
        #expect(CrashReportParser.basename("/Users/sample/App.app/Contents/MacOS/App") == "App")
        #expect(CrashReportParser.basename("libsystem_kernel.dylib") == "libsystem_kernel.dylib")
    }
}

struct CrashReportFormatterTests {
    private static let home = "/Users/sample"

    @Test func summaryExcludesPrivateFields() throws {
        let report = try CrashReportParser.parse(CrashReportFixture.ips)
        let summary = CrashReportFormatter.summary(report, homeDirectory: Self.home)
        #expect(summary.contains("NotchHub 1.3.2 (5)"))
        #expect(summary.contains("Exception: EXC_BREAKPOINT (SIGTRAP)"))
        #expect(summary.contains("Crashed thread: 1"))
        #expect(summary.contains("0  libswiftCore.dylib  closure #1 in _assertionFailure(_:_:file:line:flags:) + 400"))
        #expect(summary.contains("2  NotchHub  0x1000"))
        for secret in [CrashReportFixture.incidentID, CrashReportFixture.otherThreadSymbol, CrashReportFixture.registerValue, "/Users/", "Mac15,6"] {
            #expect(!summary.contains(secret), "\(secret)")
        }
    }

    @Test func summaryIsSanitized() {
        let report = CrashReport(
            appVersion: "1.0", appBuild: "1", osVersion: "macOS", cpuType: "ARM-64",
            exceptionType: "EXC_BAD_ACCESS", exceptionSignal: nil, exceptionCodes: nil, crashedThread: 0,
            frames: [.init(image: "X", symbol: "load /Users/sample/a.txt for a@b.com from 10.0.0.1 https://x.io/p?token=1", offset: 1)]
        )
        let summary = CrashReportFormatter.summary(report, homeDirectory: Self.home)
        #expect(!summary.contains("sample"))
        #expect(!summary.contains("a@b.com"))
        #expect(!summary.contains("10.0.0.1"))
        #expect(!summary.contains("token=1"))
        #expect(summary.contains(DiagnosticsRedactor.emailPlaceholder))
    }

    @Test func truncatesFramesToFitTheLimit() {
        let frames = (0..<15).map { CrashReport.Frame(image: "Lib", symbol: String(repeating: "s", count: 500), offset: $0) }
        let report = CrashReport(
            appVersion: "1.0", appBuild: "1", osVersion: "macOS", cpuType: "ARM-64",
            exceptionType: "EXC_CRASH", exceptionSignal: "SIGABRT", exceptionCodes: "0x0", crashedThread: 0, frames: frames
        )
        let summary = CrashReportFormatter.summary(report, homeDirectory: Self.home, maxLength: 2000)
        #expect(summary.count <= 2000)
        #expect(summary.contains("more frames truncated"))
        #expect(summary.hasPrefix("NotchHub 1.0 (1)"))
        #expect(CrashReportFormatter.summary(report, homeDirectory: Self.home).count <= CrashReportFormatter.maxBodyLength)
    }

    @Test func issueURLFitsAndMentionsManualAttachment() throws {
        let report = try CrashReportParser.parse(CrashReportFixture.ips)
        let base = try #require(DiagnosticsIssueURL.baseURL(from: "owner/repo"))
        let summary = CrashReportFormatter.summary(report, homeDirectory: Self.home)
        let url = try #require(DiagnosticsIssueURL.make(
            base: base, title: "Çökme", summary: summary, instruction: CrashReportFormatter.attachInstruction
        ))
        #expect(url.absoluteString.utf8.count <= DiagnosticsIssueURL.maxLength)
        #expect(url.absoluteString.contains(DiagnosticsIssueURL.encode(CrashReportFormatter.attachInstruction)))
    }
}

final class StubCrashReportLister: CrashReportListing, @unchecked Sendable {
    var filesByDirectory: [URL: [CrashReportFile]] = [:]
    var contents: [URL: String] = [:]

    func files(in directory: URL) throws -> [CrashReportFile] {
        guard let files = filesByDirectory[directory] else { throw CocoaError(.fileReadNoSuchFile) }
        return files
    }

    func contents(of file: URL) throws -> String {
        guard let text = contents[file] else { throw CocoaError(.fileReadNoSuchFile) }
        return text
    }
}

struct CrashReportLocatorTests {
    static let reports = URL(filePath: "/reports", directoryHint: .isDirectory)
    static let retired = URL(filePath: "/reports/Retired", directoryHint: .isDirectory)
    static let launch = Date(timeIntervalSince1970: 1_800_000_000)

    static func file(_ name: String, in directory: URL = reports, offset: TimeInterval) -> CrashReportFile {
        CrashReportFile(url: directory.appending(path: name), modified: launch.addingTimeInterval(offset))
    }

    private func locator(_ lister: StubCrashReportLister) -> CrashReportLocator {
        CrashReportLocator(directories: [Self.reports, Self.retired], processName: "NotchHub", lister: lister)
    }

    @Test func picksNewestOwnReportAfterLastLaunchAcrossDirectories() {
        let lister = StubCrashReportLister()
        lister.filesByDirectory[Self.reports] = [
            Self.file("NotchHub-old.ips", offset: -60),
            Self.file("NotchHubHelper-1.ips", offset: 90),
            Self.file("NotchHub.cpu_resource-1.diag", offset: 90),
            Self.file("NotchHub-a.ips", offset: 30),
        ]
        lister.filesByDirectory[Self.retired] = [Self.file("NotchHub-b.ips", in: Self.retired, offset: 60)]
        let found = locator(lister).newestUnhandled(since: Self.launch, handled: [])
        #expect(found?.name == "NotchHub-b.ips")
    }

    @Test func ignoresHandledReportsAndOlderOnes() {
        let lister = StubCrashReportLister()
        lister.filesByDirectory[Self.reports] = [Self.file("NotchHub-a.ips", offset: 30), Self.file("NotchHub-old.ips", offset: -1)]
        #expect(locator(lister).newestUnhandled(since: Self.launch, handled: ["NotchHub-a.ips"]) == nil)
    }

    @Test func firstLaunchNeverPrompts() {
        let lister = StubCrashReportLister()
        lister.filesByDirectory[Self.reports] = [Self.file("NotchHub-a.ips", offset: 30)]
        #expect(locator(lister).newestUnhandled(since: nil, handled: []) == nil)
    }

    @Test func recognizesOwnReportNames() {
        let locator = locator(StubCrashReportLister())
        #expect(locator.isOwnReport("NotchHub-2026-10-29-192744.ips"))
        #expect(locator.isOwnReport("NotchHub.ips"))
        #expect(!locator.isOwnReport("NotchHubHelper-2026.ips"))
        #expect(!locator.isOwnReport("NotchHub-2026.diag"))
    }
}

@MainActor
final class RecordingRevealer: CrashReportFileRevealing {
    private(set) var revealed: [URL] = []
    func reveal(_ file: URL) { revealed.append(file) }
}

@MainActor
struct CrashReportMonitorTests {
    private let defaults = TestDefaults.suite(named: "CrashReportMonitorTests.\(UUID().uuidString)")
    private let lister = StubCrashReportLister()
    private let alerts = NotchAlertCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    private let opener = RecordingURLOpener()
    private let revealer = RecordingRevealer()
    private let pasteboard = RecordingPasteboard()

    private func monitor(now: TimeInterval, issueSetting: String? = "owner/repo") -> CrashReportMonitor {
        CrashReportMonitor(
            alerts: alerts,
            ledger: CrashReportLedger(defaults: defaults),
            locator: CrashReportLocator(directories: [CrashReportLocatorTests.reports], processName: "NotchHub", lister: lister),
            urlOpener: opener,
            revealer: revealer,
            pasteboard: pasteboard,
            dependencies: .init(
                now: { CrashReportLocatorTests.launch.addingTimeInterval(now) },
                issueURLSetting: { issueSetting },
                homeDirectory: "/Users/sample"
            )
        )
    }

    private func addCrash(_ name: String, offset: TimeInterval) -> CrashReportFile {
        let file = CrashReportLocatorTests.file(name, offset: offset)
        lister.filesByDirectory[CrashReportLocatorTests.reports, default: []].append(file)
        lister.contents[file.url] = CrashReportFixture.ips
        return file
    }

    @Test func promptsOncePerReportAndBildirOpensIssueThenOffersFinder() throws {
        lister.filesByDirectory[CrashReportLocatorTests.reports] = []
        monitor(now: 0).checkOnLaunch()
        #expect(alerts.current == nil)

        let crash = addCrash("NotchHub-1.ips", offset: 10)
        let monitor = monitor(now: 20)
        #expect(monitor.checkOnLaunch() == crash)
        let prompt = try #require(alerts.current)
        #expect(prompt.title == "NotchHub beklenmedik şekilde kapandı")
        #expect(prompt.actionTitle == "Bildir")
        #expect(prompt.secondaryActionTitle == "Yoksay")

        alerts.performAction()
        let url = try #require(opener.opened.first)
        #expect(url.absoluteString.hasPrefix("https://github.com/owner/repo/issues/new?title="))
        #expect(alerts.current?.actionTitle == "Raporu Finder'da göster")
        alerts.performAction()
        #expect(revealer.revealed == [crash.url])

        #expect(CrashReportLedger(defaults: defaults).handledNames == [crash.name])
        #expect(self.monitor(now: 30).checkOnLaunch() == nil)
    }

    @Test func yoksayDismissesWithoutReporting() {
        lister.filesByDirectory[CrashReportLocatorTests.reports] = []
        monitor(now: 0).checkOnLaunch()
        _ = addCrash("NotchHub-1.ips", offset: 10)
        monitor(now: 20).checkOnLaunch()
        alerts.performSecondaryAction()
        #expect(alerts.current == nil)
        #expect(opener.opened.isEmpty)
    }

    @Test func uncleanExitWithoutReportDoesNotPrompt() {
        lister.filesByDirectory[CrashReportLocatorTests.reports] = []
        monitor(now: 0).checkOnLaunch()
        #expect(CrashReportLedger(defaults: defaults).wasRunning)
        #expect(monitor(now: 20).checkOnLaunch() == nil)
        #expect(alerts.current == nil)
    }

    @Test func cleanExitClearsSentinel() {
        let monitor = monitor(now: 0)
        monitor.checkOnLaunch()
        monitor.recordCleanExit()
        #expect(!CrashReportLedger(defaults: defaults).wasRunning)
    }

    @Test func disabledSettingSuppressesPrompt() {
        lister.filesByDirectory[CrashReportLocatorTests.reports] = []
        monitor(now: 0).checkOnLaunch()
        defaults.set(false, forKey: CrashReportLedger.promptEnabledKey)
        _ = addCrash("NotchHub-1.ips", offset: 10)
        #expect(monitor(now: 20).checkOnLaunch() == nil)
        #expect(alerts.current == nil)
    }

    @Test func withoutIssueURLCopiesSummary() {
        lister.filesByDirectory[CrashReportLocatorTests.reports] = []
        monitor(now: 0, issueSetting: nil).checkOnLaunch()
        _ = addCrash("NotchHub-1.ips", offset: 10)
        let monitor = monitor(now: 20, issueSetting: nil)
        monitor.checkOnLaunch()
        alerts.performAction()
        #expect(opener.opened.isEmpty)
        #expect(pasteboard.copied.first?.contains("EXC_BREAKPOINT") == true)
    }

    @Test func unreadableReportIsMarkedHandledWithoutPrompt() {
        lister.filesByDirectory[CrashReportLocatorTests.reports] = []
        monitor(now: 0).checkOnLaunch()
        let file = addCrash("NotchHub-1.ips", offset: 10)
        lister.contents[file.url] = "garbage"
        #expect(monitor(now: 20).checkOnLaunch() == nil)
        #expect(CrashReportLedger(defaults: defaults).handledNames == ["NotchHub-1.ips"])
    }
}

struct CrashReportLedgerTests {
    @Test func handledNamesAreDeduplicatedAndCapped() {
        let defaults = TestDefaults.suite(named: "CrashReportLedgerTests.\(UUID().uuidString)")
        let ledger = CrashReportLedger(defaults: defaults)
        ledger.markHandled("a")
        ledger.markHandled("a")
        #expect(ledger.handledNames == ["a"])
        for index in 0..<(CrashReportLedger.maxHandledNames + 5) { ledger.markHandled("n\(index)") }
        #expect(ledger.handledNames.count == CrashReportLedger.maxHandledNames)
        #expect(!ledger.handledNames.contains("a"))
        #expect(ledger.isPromptEnabled)
    }

    @Test func crashSettingIsSearchable() {
        #expect(SettingsSearchIndex.search("çökme").map(\.category).contains(.general))
        #expect(SettingsSearchIndex.search("Offer a Report After a Crash").map(\.category).contains(.general))
    }
}
