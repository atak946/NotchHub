import Foundation
import Testing
@testable import NotchHub

struct FocusGuardPolicyTests {
    private let policy = FocusGuardPolicy(gracePeriod: 10, cooldown: 120)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let active: Set<String> = ["net.whatsapp.whatsapp", "com.hnc.discord"]

    private func focus(elapsed: TimeInterval, duration: TimeInterval = 1500) -> FocusTimerSnapshot {
        FocusTimerSnapshot(state: .running(.work), remaining: duration - elapsed, phaseDuration: duration)
    }

    @Test func remindsDuringFocusAfterGrace() {
        let decision = policy.decide(
            bundleID: "net.whatsapp.WhatsApp", timer: focus(elapsed: 660), activeIDs: active, lastReminders: [:], now: now
        )
        #expect(decision == .remind(minutesLeft: 14))
        #expect(FocusGuardPolicy.reminderTitle(minutesLeft: 14) == "Odak zamanı — 14 dk kaldı")
    }

    @Test(arguments: [
        TimerState.idle, .paused(.work), .finished(.work), .running(.shortBreak), .running(.longBreak), .running(.countdown),
    ])
    func skipsOutsideRunningFocus(state: TimerState) {
        let snapshot = FocusTimerSnapshot(state: state, remaining: 600, phaseDuration: 1500)
        let decision = policy.decide(
            bundleID: "net.whatsapp.WhatsApp", timer: snapshot, activeIDs: active, lastReminders: [:], now: now
        )
        #expect(decision == .skip(.notFocusing))
        #expect(!decision.countsAsDistraction)
    }

    @Test func skipsDuringGracePeriod() {
        let decision = policy.decide(
            bundleID: "com.hnc.Discord", timer: focus(elapsed: 9.5), activeIDs: active, lastReminders: [:], now: now
        )
        #expect(decision == .skip(.gracePeriod))
        #expect(!decision.countsAsDistraction)

        let atBoundary = policy.decide(
            bundleID: "com.hnc.Discord", timer: focus(elapsed: 10), activeIDs: active, lastReminders: [:], now: now
        )
        #expect(atBoundary.isReminder)
    }

    @Test func cooldownIsPerApp() {
        let recent = ["net.whatsapp.whatsapp": now.addingTimeInterval(-60)]
        let sameApp = policy.decide(
            bundleID: "net.whatsapp.WhatsApp", timer: focus(elapsed: 300), activeIDs: active, lastReminders: recent, now: now
        )
        #expect(sameApp == .skip(.coolingDown))
        #expect(sameApp.countsAsDistraction)

        let otherApp = policy.decide(
            bundleID: "com.hnc.Discord", timer: focus(elapsed: 300), activeIDs: active, lastReminders: recent, now: now
        )
        #expect(otherApp.isReminder)

        let expired = ["net.whatsapp.whatsapp": now.addingTimeInterval(-120)]
        let afterCooldown = policy.decide(
            bundleID: "net.whatsapp.WhatsApp", timer: focus(elapsed: 300), activeIDs: active, lastReminders: expired, now: now
        )
        #expect(afterCooldown.isReminder)
    }

    @Test(arguments: [nil, "", "com.apple.Safari", "com.google.Chrome", "net.whatsapp.WhatsAppBeta"])
    func ignoresAppsNotOnTheList(bundleID: String?) {
        let decision = policy.decide(
            bundleID: bundleID, timer: focus(elapsed: 300), activeIDs: active, lastReminders: [:], now: now
        )
        #expect(decision == .skip(.notDistracting))
    }

    @Test func minutesLeftRoundsUpAndNeverShowsZero() {
        #expect(FocusGuardPolicy.minutesLeft(840) == 14)
        #expect(FocusGuardPolicy.minutesLeft(841) == 15)
        #expect(FocusGuardPolicy.minutesLeft(20) == 1)
        #expect(FocusGuardPolicy.minutesLeft(0) == 1)
    }
}

struct FocusAppListTests {
    @Test func defaultsWatchChatAppsButNotBrowsers() {
        let ids = FocusAppList.activeIDs(in: FocusApp.defaults)
        #expect(ids.contains("net.whatsapp.whatsapp"))
        #expect(ids.contains("ru.keepcoder.telegram"))
        #expect(ids.contains("com.hnc.discord"))
        #expect(!ids.contains("com.tinyspeck.slackmacgap"))
        #expect(FocusApp.defaults.contains { $0.bundleID == "com.tinyspeck.slackmacgap" })
        #expect(!FocusApp.defaults.contains { $0.bundleID == "com.apple.Safari" || $0.bundleID == "com.google.Chrome" })
    }

    @Test func matchingIsCaseInsensitive() {
        let ids = FocusAppList.activeIDs(in: [FocusApp(bundleID: "Net.WhatsApp.WhatsApp", name: "WhatsApp")])
        #expect(FocusAppList.matches("net.whatsapp.whatsapp", in: ids))
        #expect(!FocusAppList.matches(nil, in: ids))
    }

    @Test func editingIsImmutableAndDeduplicated() {
        let original = [FocusApp(bundleID: "a.b", name: "A")]
        let added = FocusAppList.adding(FocusApp(bundleID: "c.d", name: "C"), to: original)
        let duplicate = FocusAppList.adding(FocusApp(bundleID: "A.B", name: "Again"), to: added)
        let empty = FocusAppList.adding(FocusApp(bundleID: "", name: "Nothing"), to: added)
        let disabled = FocusAppList.setting("a.b", enabled: false, in: added)
        let removed = FocusAppList.removing("a.b", from: added)

        #expect(original.count == 1)
        #expect(added.map(\.bundleID) == ["a.b", "c.d"])
        #expect(duplicate == added)
        #expect(empty == added)
        #expect(disabled.first?.isEnabled == false)
        #expect(added.first?.isEnabled == true)
        #expect(removed.map(\.bundleID) == ["c.d"])
    }

    @Test func roundTripsThroughJSON() {
        let apps = [FocusApp(bundleID: "a.b", name: "A", isEnabled: false)]
        #expect(FocusAppList.decode(FocusAppList.encode(apps)) == apps)
        #expect(FocusAppList.decode(Data("junk".utf8)) == nil)
        #expect(FocusAppList.decode(nil) == nil)
    }
}

struct FocusDistractionLogTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .gmt
        return calendar
    }

    @Test func countsPerDayAndResetsAtMidnight() {
        let morning = Date(timeIntervalSince1970: 1_800_000_000)
        let log = FocusDistractionLog.empty(on: morning, calendar: calendar)
            .incremented(on: morning, calendar: calendar)
            .incremented(on: morning, calendar: calendar)
        #expect(log.count(on: morning, calendar: calendar) == 2)

        let tomorrow = morning.addingTimeInterval(86_400)
        #expect(log.count(on: tomorrow, calendar: calendar) == 0)
        #expect(log.incremented(on: tomorrow, calendar: calendar).count == 1)
    }
}
