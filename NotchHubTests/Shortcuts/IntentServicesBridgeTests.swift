import Foundation
import Testing
@testable import NotchHub

@MainActor
final class FakeIntentRoutes: IntentRouting {
    var enabledModules = Set(NotchModule.allCases)
    var canPostAlerts = true
    var profiles: [IntentProfile] = []
    var isProfileBusy = false
    var isMicMuteAvailable = true
    private(set) var isMicMuted = false

    private(set) var timerDurations: [TimeInterval] = []
    private(set) var notes: [String] = []
    private(set) var ranProfiles: [UUID] = []
    private(set) var alerts: [(title: String, message: String?, style: NotchAlert.Style)] = []
    private(set) var opened: [NotchModule] = []
    private(set) var toggled: [NotchModule] = []

    func isModuleEnabled(_ module: NotchModule) -> Bool { enabledModules.contains(module) }
    func startTimer(duration: TimeInterval) { timerDurations.append(duration) }
    func addNote(text: String) { notes.append(text) }

    func runProfile(id: UUID) -> Bool {
        guard !isProfileBusy else { return false }
        ranProfiles.append(id)
        return true
    }

    func postAlert(title: String, message: String?, style: NotchAlert.Style) {
        alerts.append((title, message, style))
    }

    func open(_ module: NotchModule) { opened.append(module) }
    func toggle(_ module: NotchModule) { toggled.append(module) }

    func toggleMicMute() -> Bool {
        isMicMuted.toggle()
        return isMicMuted
    }
}

@MainActor
struct IntentServicesBridgeTests {
    private let routes = FakeIntentRoutes()
    private var bridge: IntentServicesBridge { IntentServicesBridge(routes: routes, sleep: { _ in }) }

    @Test func failsGracefullyWhenAppIsNotReady() async {
        let bridge = IntentServicesBridge(routes: nil, sleep: { _ in })

        await #expect(throws: IntentBridgeError.notReady) {
            try await bridge.startTimer(minutes: 5)
        }
        #expect(IntentBridgeError.notReady.errorDescription?.isEmpty == false)
    }

    @Test func waitsForConfigurationDuringLaunch() async throws {
        let routes = routes
        let box = BridgeBox()
        let bridge = IntentServicesBridge(routes: nil, sleep: { _ in
            await MainActor.run { box.bridge?.configure(routes) }
        })
        box.bridge = bridge

        try await bridge.open(.notes)

        #expect(routes.opened == [.notes])
    }

    @Test func startsTimerInSecondsAndValidatesRange() async throws {
        try await bridge.startTimer(minutes: 25)

        #expect(routes.timerDurations == [1500])
        await #expect(throws: IntentBridgeError.invalidDuration) { try await bridge.startTimer(minutes: 0) }
        await #expect(throws: IntentBridgeError.invalidDuration) { try await bridge.startTimer(minutes: 181) }
    }

    @Test func refusesDisabledModules() async {
        routes.enabledModules = [.shelf]

        await #expect(throws: IntentBridgeError.moduleDisabled(.timer)) { try await bridge.startTimer(minutes: 5) }
        await #expect(throws: IntentBridgeError.moduleDisabled(.notes)) { try await bridge.addNote(text: "x") }
        await #expect(throws: IntentBridgeError.moduleDisabled(.media)) { try await bridge.open(.media) }
        #expect(routes.timerDurations.isEmpty)
        #expect(routes.opened.isEmpty)
    }

    @Test func addsTrimmedNotesAndRejectsBlankText() async throws {
        try await bridge.addNote(text: "  buy milk \n")

        #expect(routes.notes == ["buy milk"])
        await #expect(throws: IntentBridgeError.emptyText) { try await bridge.addNote(text: " \n ") }
    }

    @Test func runsKnownProfilesOnly() async throws {
        let profile = IntentProfile(id: UUID(), name: "Acme")
        routes.profiles = [profile]

        let started = try await bridge.runProfile(id: profile.id)

        #expect(started == profile)
        #expect(routes.ranProfiles == [profile.id])
        #expect(try await bridge.profiles() == [profile])
        await #expect(throws: IntentBridgeError.profileNotFound) { try await bridge.runProfile(id: UUID()) }
        routes.isProfileBusy = true
        await #expect(throws: IntentBridgeError.profileBusy) { try await bridge.runProfile(id: profile.id) }
    }

    @Test func postsSanitizedAlerts() async throws {
        try await bridge.showAlert(title: "  Build\n done ", message: "  ", style: .success)

        #expect(routes.alerts.count == 1)
        #expect(routes.alerts.first?.title == "Build done")
        #expect(routes.alerts.first?.message == nil)
        #expect(routes.alerts.first?.style == .success)
        await #expect(throws: IntentBridgeError.emptyTitle) { try await bridge.showAlert(title: "\n", message: nil, style: .info) }
    }

    @Test func refusesAlertsWhileAlertsAreOff() async {
        routes.canPostAlerts = false

        await #expect(throws: IntentBridgeError.alertsUnavailable) {
            try await bridge.showAlert(title: "Hi", message: nil, style: .info)
        }
        #expect(routes.alerts.isEmpty)
    }

    @Test func opensAndTogglesModules() async throws {
        try await bridge.open(.calendar)
        try await bridge.toggle(.shelf)

        #expect(routes.opened == [.calendar])
        #expect(routes.toggled == [.shelf])
    }

    @Test func togglesMicMuteWhenAvailable() async throws {
        #expect(try await bridge.toggleMicMute())
        #expect(try await bridge.toggleMicMute() == false)

        routes.isMicMuteAvailable = false
        await #expect(throws: IntentBridgeError.micUnavailable) { try await bridge.toggleMicMute() }
    }

    @Test func intentEnumsMapToAppTypes() {
        #expect(IntentModule.allCases.map(\.notchModule) == NotchModule.allCases)
        #expect(IntentAlertStyle.urgent.notchStyle == .urgent)
        #expect(LiveIntentRoutes.alertAppName == "Kestirmeler")
        #expect(IntentLimits.timerMinutes == TimerService.customMinutesRange)
    }
}

@MainActor
private final class BridgeBox {
    var bridge: IntentServicesBridge?
}
