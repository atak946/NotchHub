import AppIntents
import Foundation

// Thin App Intents: each one validates nothing itself and defers to `IntentServicesBridge`.

struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Zamanlayıcıyı Başlat"
    static let description = IntentDescription("NotchHub'da geri sayım başlatır.")

    @Parameter(title: "Dakika", default: 25, inclusiveRange: (1, 180))
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$minutes) dakikalık zamanlayıcı başlat")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentServicesBridge.shared.startTimer(minutes: minutes)
        return .result(dialog: "\(minutes) dakikalık zamanlayıcı başladı.")
    }
}

struct AddNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Not Ekle"
    static let description = IntentDescription("NotchHub notlarına yeni bir not ekler.")

    @Parameter(title: "Metin", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$text) notunu ekle")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentServicesBridge.shared.addNote(text: text)
        return .result(dialog: "Not eklendi.")
    }
}

struct RunProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Profili Çalıştır"
    static let description = IntentDescription("Bir müşteri profilinin adımlarını çalıştırır.")

    @Parameter(title: "Profil")
    var profile: ProfileEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$profile) profilini çalıştır")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let started = try await IntentServicesBridge.shared.runProfile(id: profile.id)
        return .result(dialog: "\(started.name) profili çalışıyor.")
    }
}

struct ShowNotchAlertIntent: AppIntent {
    static let title: LocalizedStringResource = "Çentik Uyarısı Göster"
    static let description = IntentDescription("Çentikten açılan bir uyarı gösterir.")

    @Parameter(title: "Başlık")
    var title: String

    @Parameter(title: "Mesaj")
    var message: String?

    @Parameter(title: "Tür", default: .info)
    var style: IntentAlertStyle

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$title) uyarısını göster") {
            \.$message
            \.$style
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await IntentServicesBridge.shared.showAlert(title: title, message: message, style: style.notchStyle)
        return .result()
    }
}

struct OpenModuleIntent: AppIntent {
    static let title: LocalizedStringResource = "Modülü Aç"
    static let description = IntentDescription("Çentik panelini seçilen modülde açar.")

    @Parameter(title: "Modül", default: .shelf)
    var module: IntentModule

    static var parameterSummary: some ParameterSummary {
        Summary("Paneli \(\.$module) modülünde aç")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await IntentServicesBridge.shared.open(module.notchModule)
        return .result()
    }
}

struct ToggleShelfIntent: AppIntent {
    static let title: LocalizedStringResource = "Rafı Aç/Kapat"
    static let description = IntentDescription("Panel kapalıysa Dosya Rafı'nda açar, açıksa kapatır.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try await IntentServicesBridge.shared.toggle(.shelf)
        return .result()
    }
}

struct ToggleMicMuteIntent: AppIntent {
    static let title: LocalizedStringResource = "Mikrofonu Sustur/Aç"
    static let description = IntentDescription("Sistem mikrofonunu susturur ya da yeniden açar.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let isMuted = try await IntentServicesBridge.shared.toggleMicMute()
        return .result(dialog: isMuted ? "Mikrofon kapatıldı." : "Mikrofon açıldı.")
    }
}
