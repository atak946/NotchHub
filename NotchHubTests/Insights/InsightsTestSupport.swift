import Foundation
import Synchronization
@testable import NotchHub

final class InsightsTestClock: InsightsClock {
    private let storage: Mutex<Date>

    init(_ date: Date) {
        storage = Mutex(date)
    }

    var now: Date { storage.withLock { $0 } }

    func set(_ date: Date) {
        storage.withLock { $0 = date }
    }

    func advance(by interval: TimeInterval) {
        storage.withLock { $0 = $0.addingTimeInterval(interval) }
    }

    /// Never returns before cancellation; tests drive `poll()` / `sample()` directly.
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: .seconds(3600))
    }
}

final class InsightsFakeTrust: AccessibilityTrustChecking {
    private let state: Mutex<(trusted: Bool, prompts: Int, silentChecks: Int)>
    private let opened = Mutex(0)

    init(trusted: Bool) {
        state = Mutex((trusted, 0, 0))
    }

    var trusted: Bool {
        get { state.withLock { $0.trusted } }
        set { state.withLock { $0.trusted = newValue } }
    }

    var promptCount: Int { state.withLock { $0.prompts } }
    var settingsOpenCount: Int { opened.withLock { $0 } }

    func isTrusted(prompt: Bool) -> Bool {
        state.withLock {
            if prompt { $0.prompts += 1 } else { $0.silentChecks += 1 }
            return $0.trusted
        }
    }

    @MainActor
    func openSystemSettings() {
        opened.withLock { $0 += 1 }
    }
}

final class InsightsFakeBadgeReader: DockBadgeReading {
    private let storage: Mutex<(badges: [String: Int]?, reads: Int)>

    init(_ badges: [String: Int]? = [:]) {
        storage = Mutex((badges, 0))
    }

    var badges: [String: Int]? {
        get { storage.withLock { $0.badges } }
        set { storage.withLock { $0.badges = newValue } }
    }

    var readCount: Int { storage.withLock { $0.reads } }

    func readBadges() -> [String: Int]? {
        storage.withLock {
            $0.reads += 1
            return $0.badges
        }
    }
}

@MainActor
final class InsightsFakeActivator: InsightsAppActivating {
    private(set) var activated: [String] = []

    func activate(appNamed name: String) {
        activated.append(name)
    }
}

@MainActor
final class InsightsFakePasteboard: InsightsPasteboard {
    private(set) var copied: [String] = []

    func copy(_ text: String) {
        copied.append(text)
    }
}

final class InsightsFakeProbe: ActivityProbing {
    struct State {
        var bundleID: String?
        var window: FocusedWindowInfo?
        var idle: TimeInterval = 0
        var windowReads = 0
    }

    private let storage = Mutex(State())

    func set(bundleID: String?, title: String? = nil, path: String? = nil, idle: TimeInterval = 0) {
        storage.withLock {
            $0.bundleID = bundleID
            $0.window = FocusedWindowInfo(title: title, documentPath: path)
            $0.idle = idle
        }
    }

    func setIdle(_ seconds: TimeInterval) {
        storage.withLock { $0.idle = seconds }
    }

    var windowReads: Int { storage.withLock { $0.windowReads } }

    @MainActor
    func frontmostBundleID() -> String? {
        storage.withLock { $0.bundleID }
    }

    func idleSeconds() -> TimeInterval {
        storage.withLock { $0.idle }
    }

    func focusedWindow() -> FocusedWindowInfo? {
        storage.withLock {
            $0.windowReads += 1
            return $0.window
        }
    }
}

final class InsightsMemoryLedgerStore: TimeLedgerStoring {
    private let storage: Mutex<(ledger: TimeLedger?, saves: Int)>

    init(_ ledger: TimeLedger? = nil) {
        storage = Mutex((ledger, 0))
    }

    var saved: TimeLedger? { storage.withLock { $0.ledger } }
    var saveCount: Int { storage.withLock { $0.saves } }

    func load() throws -> TimeLedger {
        storage.withLock { $0.ledger ?? .empty }
    }

    func save(_ ledger: TimeLedger) throws {
        storage.withLock {
            $0.ledger = ledger
            $0.saves += 1
        }
    }

    func delete() throws {
        storage.withLock { $0.ledger = nil }
    }
}

enum InsightsTestDates {
    /// Gregorian, Istanbul (no DST), weeks start Monday.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .gmt
        calendar.firstWeekday = 2
        return calendar
    }()

    /// A time on 2026-10-28, a Wednesday.
    static func date(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        date(2026, 10, 28, hour, minute, second)
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}

func makeInsightsTestDefaults() -> UserDefaults {
    let (suiteName, defaults) = TestDefaults.makeSuite("Insights.\(UUID().uuidString)")
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
