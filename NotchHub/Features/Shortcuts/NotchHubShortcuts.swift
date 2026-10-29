import AppIntents

/// Ready-made Shortcuts and Siri phrases (Turkish).
struct NotchHubShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTimerIntent(),
            phrases: [
                "\(.applicationName) zamanlayıcı başlat",
                "\(.applicationName) ile geri sayım başlat",
            ],
            shortTitle: "Zamanlayıcı",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: AddNoteIntent(),
            phrases: [
                "\(.applicationName) not ekle",
                "\(.applicationName) ile not al",
            ],
            shortTitle: "Not Ekle",
            systemImageName: "note.text.badge.plus"
        )
        AppShortcut(
            intent: RunProfileIntent(),
            phrases: [
                "\(.applicationName) profil çalıştır",
                "\(.applicationName) ile \(\.$profile) profilini çalıştır",
            ],
            shortTitle: "Profil Çalıştır",
            systemImageName: "person.crop.rectangle.stack"
        )
        AppShortcut(
            intent: ToggleShelfIntent(),
            phrases: [
                "\(.applicationName) rafı aç",
                "\(.applicationName) rafını göster",
            ],
            shortTitle: "Raf",
            systemImageName: "tray.full"
        )
        AppShortcut(
            intent: ToggleMicMuteIntent(),
            phrases: [
                "\(.applicationName) mikrofonu sustur",
                "\(.applicationName) ile mikrofonu aç kapat",
            ],
            shortTitle: "Mikrofon",
            systemImageName: "mic.slash"
        )
    }
}
