import Testing
@testable import NotchHub

@MainActor
struct UpdateReminderAlertTests {
    @Test func reminderDescribesTheUpdate() {
        let alert = UpdateReminderAlert.make(version: "1.3.0") {}

        #expect(alert.title == "NotchHub 1.3.0 hazır")
        #expect(alert.subtitle == "Güncellemek için tıkla")
        #expect(alert.actionTitle == "Güncelle")
        #expect(alert.style == .info)
        #expect(alert.appName == "NotchHub")
        #expect(alert.sourceLabel == "NotchHub")
        #expect(alert.module == nil)
        #expect(alert.coalescingKey == UpdateReminderAlert.coalescingKey)
        #expect(alert.autoDismissAfter == UpdateReminderAlert.duration)
    }

    @Test func actionBringsUpTheUpdater() {
        var didOpenUpdater = false
        let center = NotchAlertCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        center.post(UpdateReminderAlert.make(version: "1.3.0") { didOpenUpdater = true })

        center.performAction()

        #expect(didOpenUpdater)
        #expect(center.current == nil)
    }

    @Test func repeatedRemindersReplaceEachOther() {
        let center = NotchAlertCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })

        center.post(UpdateReminderAlert.make(version: "1.3.0") {})
        center.post(UpdateReminderAlert.make(version: "1.3.1") {})

        #expect(center.current?.title == "NotchHub 1.3.1 hazır")
        #expect(center.queue.isEmpty)
    }
}
