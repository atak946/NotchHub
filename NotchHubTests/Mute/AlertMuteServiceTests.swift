import Foundation
import Observation
import Testing
@testable import NotchHub

@MainActor
@Observable
private final class MuteInputs {
    var isInMeeting = false
    var isInFocus = false
}

@MainActor
struct AlertMuteServiceTests {
    private let defaults = TestDefaults.suite(named: "AlertMute.\(UUID().uuidString)")
    private let alerts = NotchAlertCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    private let inputs = MuteInputs()

    private func makeService() -> AlertMuteService {
        let inputs = inputs
        let service = AlertMuteService(
            alerts: alerts, isInMeeting: { inputs.isInMeeting }, isInFocus: { inputs.isInFocus }, defaults: defaults
        )
        service.start()
        return service
    }

    private func alert(_ title: String, app: String? = nil, _ behavior: AlertMuteBehavior) -> NotchAlert {
        NotchAlert(module: nil, systemImage: "bell", title: title, appName: app, muteBehavior: behavior)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func automaticMutingIsOffByDefault() {
        let service = makeService()
        #expect(!service.mutesInMeetings)
        #expect(!service.mutesInFocus)
        #expect(service.allowsTimeSensitive)
        #expect(!service.isMuted)
    }

    @Test func mutedAlertsAreHeldDroppedOrShown() {
        let service = makeService()
        service.mute(for: .untilTurnedOff)
        alerts.post(alert("Message", .hold))
        alerts.post(alert("Track", .drop))
        #expect(alerts.current == nil)
        #expect(service.held.map(\.title) == ["Message"])

        alerts.post(alert("Remote session", .always))
        #expect(alerts.current?.title == "Remote session")
    }

    @Test func mutingTakesDownTheCurrentAlertAndHoldsTheQueue() {
        let service = makeService()
        alerts.post(alert("Shown", .hold))
        alerts.post(alert("Queued", .hold))
        service.mute(for: .oneHour)
        #expect(alerts.current == nil)
        #expect(alerts.queue.isEmpty)
        #expect(service.held.map(\.title) == ["Queued"])
    }

    @Test func unmutingSummarizesAndReplaysHeldAlerts() {
        let service = makeService()
        service.mute(for: .oneHour)
        alerts.post(alert("One", app: "Chat", .hold))
        alerts.post(alert("Two", app: "Chat", .hold))
        service.unmute()
        #expect(!service.isMuted)
        #expect(alerts.current?.subtitle == "Chat 2")

        alerts.performAction()
        #expect(alerts.current?.title == "One")
        #expect(alerts.queue.map(\.title) == ["Two"])
        #expect(service.held.isEmpty)
    }

    @Test func unmutingWithNothingHeldPostsNothing() {
        let service = makeService()
        service.mute(for: .oneHour)
        service.unmute()
        #expect(alerts.current == nil)
    }

    @Test func meetingsMuteOnlyWhenEnabled() async {
        let service = makeService()
        inputs.isInMeeting = true
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!service.isMuted)

        service.mutesInMeetings = true
        await waitUntil { service.reason == .meeting }
        #expect(service.reason == .meeting)

        inputs.isInMeeting = false
        await waitUntil { !service.isMuted }
        #expect(!service.isMuted)
    }

    @Test func unmutingInAMeetingLastsUntilThatMeetingEnds() async {
        let service = makeService()
        service.mutesInMeetings = true
        inputs.isInMeeting = true
        await waitUntil { service.isMuted }
        service.unmute()
        #expect(!service.isMuted)

        inputs.isInMeeting = false
        try? await Task.sleep(for: .milliseconds(50))
        inputs.isInMeeting = true
        await waitUntil { service.isMuted }
        #expect(service.reason == .meeting)
    }

    @Test func heldAlertsAreBounded() {
        let service = makeService()
        service.mute(for: .untilTurnedOff)
        for index in 0..<(AlertMuteService.maxHeldAlerts + 5) { alerts.post(alert("\(index)", .hold)) }
        #expect(service.held.count == AlertMuteService.maxHeldAlerts)
        #expect(service.held.last?.title == "\(AlertMuteService.maxHeldAlerts + 4)")
    }

    @Test func stoppingLetsEverythingThrough() {
        let service = makeService()
        service.mute(for: .untilTurnedOff)
        service.stop()
        alerts.post(alert("Message", .hold))
        #expect(alerts.current?.title == "Message")
    }
}
