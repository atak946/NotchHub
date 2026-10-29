import Testing
@testable import NotchHub

@MainActor
struct NotchAlertCenterTests {
    /// Never returns, so auto-dismiss never fires during queue tests.
    private static let neverSleep: NotchAlertCenter.Sleeper = { _ in
        try await Task.sleep(for: .seconds(3600))
    }

    private func alert(_ title: String, key: String? = nil, action: (@MainActor () -> Void)? = nil) -> NotchAlert {
        NotchAlert(module: .timer, systemImage: "timer", title: title, coalescingKey: key, action: action)
    }

    @Test func showsFirstAlertAndQueuesTheRest() {
        let center = NotchAlertCenter(sleep: Self.neverSleep)

        center.post(alert("A"))
        center.post(alert("B"))

        #expect(center.current?.title == "A")
        #expect(center.queue.map(\.title) == ["B"])
    }

    @Test func dismissAdvancesQueue() {
        let center = NotchAlertCenter(sleep: Self.neverSleep)
        center.post(alert("A"))
        center.post(alert("B"))

        center.dismiss()
        #expect(center.current?.title == "B")

        center.dismiss()
        #expect(center.current == nil)
        #expect(center.queue.isEmpty)
    }

    @Test func coalescingKeyReplacesCurrentAlert() {
        let center = NotchAlertCenter(sleep: Self.neverSleep)
        center.post(alert("Song 1", key: "track"))

        center.post(alert("Song 2", key: "track"))

        #expect(center.current?.title == "Song 2")
        #expect(center.queue.isEmpty)
    }

    @Test func coalescingKeyReplacesQueuedAlert() {
        let center = NotchAlertCenter(sleep: Self.neverSleep)
        center.post(alert("Meeting"))
        center.post(alert("Song 1", key: "track"))

        center.post(alert("Song 2", key: "track"))

        #expect(center.queue.map(\.title) == ["Song 2"])
    }

    @Test func queueIsBounded() {
        let center = NotchAlertCenter(sleep: Self.neverSleep)
        center.post(alert("current"))

        for index in 0..<(NotchAlertCenter.maxQueuedAlerts + 3) {
            center.post(alert("q\(index)"))
        }

        #expect(center.queue.count == NotchAlertCenter.maxQueuedAlerts)
        #expect(center.queue.last?.title == "q\(NotchAlertCenter.maxQueuedAlerts + 2)")
    }

    @Test func performActionRunsActionAndDismisses() {
        let center = NotchAlertCenter(sleep: Self.neverSleep)
        var didRun = false
        center.post(alert("Join", action: { didRun = true }))

        center.performAction()

        #expect(didRun)
        #expect(center.current == nil)
    }

    @Test func dismissAllClearsQueue() {
        let center = NotchAlertCenter(sleep: Self.neverSleep)
        center.post(alert("A"))
        center.post(alert("B"))

        center.dismissAll()

        #expect(center.current == nil)
        #expect(center.queue.isEmpty)
    }

    @Test func autoDismissesAfterDuration() async {
        let center = NotchAlertCenter(sleep: { _ in })
        center.post(alert("A"))

        for _ in 0..<20 where center.current != nil {
            await Task.yield()
        }

        #expect(center.current == nil)
    }

    @Test func hoverPreventsAutoDismiss() async {
        let center = NotchAlertCenter(sleep: { _ in })
        center.post(alert("A"))
        center.isHovered = true

        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(center.current?.title == "A")
    }

    @Test func exposesCountdownForAutoDismissingAlerts() {
        let start = ContinuousClock.now
        let center = NotchAlertCenter(sleep: Self.neverSleep, now: { start })

        center.post(alert("A"))

        #expect(center.countdown == AlertCountdown.started(total: NotchAlert.defaultDuration, at: start))
    }

    @Test func persistentAlertsHaveNoCountdown() {
        let center = NotchAlertCenter(sleep: Self.neverSleep)

        center.post(NotchAlert(module: .calendar, systemImage: "calendar", title: "Toplantı", autoDismissAfter: nil))

        #expect(center.countdown == nil)
    }

    @Test func hoverPausesAndResumesCountdown() {
        let center = NotchAlertCenter(sleep: Self.neverSleep)
        center.post(alert("A"))

        center.isHovered = true
        #expect(center.countdown?.isRunning == false)

        center.isHovered = false
        #expect(center.countdown?.isRunning == true)
    }

    @Test func dismissClearsCountdown() {
        let center = NotchAlertCenter(sleep: Self.neverSleep)
        center.post(alert("A"))

        center.dismiss()

        #expect(center.countdown == nil)
    }
}
