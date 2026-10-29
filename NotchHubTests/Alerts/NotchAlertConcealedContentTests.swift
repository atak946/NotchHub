import Synchronization
import Testing
@testable import NotchHub

@MainActor
struct NotchAlertConcealedContentTests {
    private static let neverSleep: NotchAlertCenter.Sleeper = { _ in try await Task.sleep(for: .seconds(3600)) }

    private func concealed(duration: Duration? = .seconds(6)) -> NotchAlert {
        NotchAlert(
            module: .status, systemImage: "message.fill", title: "Ahmet Yılmaz", subtitle: "İçerik gizlendi",
            autoDismissAfter: duration, actionTitle: "Aç", action: {}, sender: "Ahmet Yılmaz",
            concealedSubtitle: "Gizli mesaj"
        )
    }

    @Test func concealedAlertOnlyExposesThePlaceholder() {
        let alert = concealed()
        #expect(alert.isContentConcealed)
        #expect(!alert.isContentRevealed)
        #expect(alert.subtitle == "İçerik gizlendi")
        #expect(alert.displayedSubtitle == "İçerik gizlendi")
        #expect(alert.sender == "Ahmet Yılmaz")
    }

    @Test func revealingKeepsIdentityAndShowsText() {
        let alert = concealed()
        let revealed = alert.revealingContent()
        #expect(revealed.id == alert.id)
        #expect(revealed.isContentRevealed)
        #expect(!revealed.isContentConcealed)
        #expect(revealed.displayedSubtitle == "Gizli mesaj")
        #expect(alert.isContentConcealed, "the original value is not mutated")
    }

    @Test func plainAlertsAreNeverConcealed() {
        let plain = NotchAlert(module: .timer, systemImage: "timer", title: "Mola", subtitle: "Bitti")
        #expect(!plain.isContentConcealed)
        #expect(plain.displayedSubtitle == "Bitti")
        #expect(!plain.revealingContent().isContentRevealed)
        let blank = NotchAlert(module: .timer, systemImage: "timer", title: "Mola", concealedSubtitle: "  ")
        #expect(!blank.isContentConcealed)
    }

    @Test func centerRevealRestartsCountdownAndKeepsAction() {
        let clock = Mutex(ContinuousClock.now)
        let start = clock.withLock { $0 }
        let center = NotchAlertCenter(sleep: Self.neverSleep, now: { clock.withLock { $0 } })
        center.post(concealed(duration: .seconds(3)))
        clock.withLock { $0 = start + .seconds(2) }

        center.revealContent()

        let current = center.current
        #expect(current?.displayedSubtitle == "Gizli mesaj")
        #expect(current?.actionTitle == "Aç")
        #expect(center.countdown == AlertCountdown.started(total: NotchAlert.defaultDuration, at: start + .seconds(2)))
    }

    @Test func revealWhileHoveredStaysPaused() {
        let center = NotchAlertCenter(sleep: Self.neverSleep)
        center.post(concealed())
        center.isHovered = true
        center.revealContent()
        #expect(center.current?.isContentRevealed == true)
        #expect(center.countdown?.isRunning == false)
    }

    @Test func revealIsANoOpWithoutConcealedContent() {
        let start = ContinuousClock.now
        let center = NotchAlertCenter(sleep: Self.neverSleep, now: { start })
        center.post(NotchAlert(module: .timer, systemImage: "timer", title: "Mola"))
        let before = center.countdown
        center.revealContent()
        #expect(center.countdown == before)
        #expect(center.current?.isContentRevealed == false)
    }

    @Test func persistentConcealedAlertStaysPersistentAfterReveal() {
        let center = NotchAlertCenter(sleep: Self.neverSleep)
        center.post(concealed(duration: nil))
        center.revealContent()
        #expect(center.countdown == nil)
        #expect(center.current?.isContentRevealed == true)
    }
}
