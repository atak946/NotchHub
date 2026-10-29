import Testing
@testable import NotchHub

struct NotchAlertFieldsTests {
    @Test func existingCallSitesKeepDefaults() {
        let alert = NotchAlert(module: .timer, systemImage: "timer", title: "Süre doldu")

        #expect(alert.appBundleID == nil)
        #expect(alert.appName == nil)
        #expect(alert.sender == nil)
        #expect(alert.timestampText == nil)
        #expect(alert.sourceLabel == NotchModule.timer.title)
    }

    @Test func blankFieldsAreTreatedAsMissing() {
        let alert = NotchAlert(module: nil, systemImage: "bell", title: "X", appName: "  ", sender: "")

        #expect(alert.appName == nil)
        #expect(alert.sender == nil)
        #expect(alert.sourceLabel == "NotchHub")
    }

    @Test func appNameBecomesSourceLabel() {
        let alert = NotchAlert(
            module: .status, systemImage: "message.fill", title: "Ayşe",
            appBundleID: "net.whatsapp.WhatsApp", appName: " WhatsApp ", sender: "Ayşe Kaya"
        )

        #expect(alert.sourceLabel == "WhatsApp")
        #expect(alert.appBundleID == "net.whatsapp.WhatsApp")
        #expect(alert.sender == "Ayşe Kaya")
    }
}
