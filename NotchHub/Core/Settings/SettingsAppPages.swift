import AppKit
import OSLog
import SwiftUI

/// Genel: launch, pause, language, updates and support.
struct GeneralSettingsPage: View {
    @Bindable var settings: SettingsStore
    let language: AppLanguageSettings
    let updater: UpdaterService
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Settings")

    var body: some View {
        Section("Genel") {
            Toggle("Girişte başlat", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    updateLaunchAtLogin(newValue)
                }
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Toggle("NotchHub'ı Duraklat", isOn: $settings.isPaused)
        }
        LanguageSettingsSection(language: language)
        UpdatesSettingsSection(updater: updater)
        SupportSettingsSection()
    }

    private func updateLaunchAtLogin(_ isEnabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(isEnabled)
            launchAtLoginError = nil
        } catch {
            logger.error("Launch at login update failed: \(error.localizedDescription)")
            launchAtLoginError = String(localized: "Giriş öğesi güncellenemedi: \(error.localizedDescription)")
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

private struct LanguageSettingsSection: View {
    @Bindable var language: AppLanguageSettings
    @State private var relaunchFailed = false

    var body: some View {
        Section("Dil") {
            Picker("Dil", selection: $language.selection) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            if language.needsRelaunch {
                LabeledContent {
                    Button("Yeniden başlat") {
                        relaunchFailed = !AppRelauncher.relaunch()
                    }
                } label: {
                    Text("Dil değişikliği yeniden başlatınca uygulanır.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if relaunchFailed {
                    Text("Yeniden başlatılamadı. NotchHub'ı kapatıp yeniden aç.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

/// Çentik ve Görünüm: behavior, displays, theme and panel tabs.
struct NotchAppearanceSettingsPage: View {
    private static let hoverSliderWidth: CGFloat = 180
    private static let hoverValueWidth: CGFloat = 56

    @Bindable var settings: SettingsStore

    var body: some View {
        Section("Davranış") {
            LabeledContent("Üzerine gelme gecikmesi") {
                HStack {
                    Slider(value: $settings.hoverDelay, in: SettingsStore.hoverDelayRange, step: 0.05)
                        .frame(width: Self.hoverSliderWidth)
                    Text("\(Int(settings.hoverDelay * 1000)) ms")
                        .monospacedDigit()
                        .frame(width: Self.hoverValueWidth, alignment: .trailing)
                }
            }
            Toggle("Uygulama tam ekranken gizle", isOn: $settings.hideInFullScreen)
        }

        Section("Ekranlar") {
            Picker("Gösterilecek ekran", selection: $settings.displayMode) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Toggle("Çentiği olmayan ekranlarda sanal çentik", isOn: $settings.showOnScreensWithoutNotch)
        }

        Section("Görünüm") {
            Picker("Tema", selection: $settings.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.segmented)
        }

        Section("Panel Sekmeleri") {
            ForEach(NotchModule.allCases) { module in
                Toggle(isOn: moduleBinding(module)) {
                    Label(module.title, systemImage: module.systemImage)
                }
            }
        }
    }

    private func moduleBinding(_ module: NotchModule) -> Binding<Bool> {
        Binding(
            get: { settings.isEnabled(module) },
            set: { settings.setModule(module, enabled: $0) }
        )
    }
}

/// Uyarılar: notch alert toggles.
struct NotchAlertsSettingsSection: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Section("Çentik Uyarıları") {
            Toggle("Çentikten animasyonlu uyarılar", isOn: $settings.alertsEnabled)
            Toggle("Parça değişimlerini göster", isOn: $settings.showTrackChangeAlerts)
                .disabled(!settings.alertsEnabled)
        }
    }
}

/// Medya: compact media controls and the music visualizer.
struct MediaSettingsSection: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Section("Medya") {
            Toggle("Kapalıyken medya kontrolleri", isOn: $settings.showsCompactMediaControls)
            Toggle("Müzik dalgası", isOn: $settings.showsMediaVisualizer)
        }
    }
}

/// Kestirmeler: global hotkeys and the Shortcuts app actions.
struct ShortcutsSettingsPage: View {
    private static let panelHotKey = "⌥⌘N"
    private static let shortcutsAppURL = URL(string: "shortcuts://")

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Settings")

    var body: some View {
        Section("Klavye kısayolları") {
            LabeledContent("Paneli aç/kapat", value: Self.panelHotKey)
            LabeledContent("Mikrofonu sustur/aç", value: MicMuteHotKey.displayName)
        }
        Section("Kestirmeler uygulaması") {
            Text("NotchHub eylemleri Kestirmeler uygulamasında ve Siri'de görünür: zamanlayıcı başlat, not ekle, profil çalıştır, uyarı göster, modül aç, rafı aç ve mikrofonu sustur.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Kestirmeler'i Aç", action: openShortcuts)
        }
    }

    private func openShortcuts() {
        guard let url = Self.shortcutsAppURL, NSWorkspace.shared.open(url) else {
            logger.error("Could not open the Shortcuts app")
            return
        }
    }
}

/// Accessibility permission status, shown on every page whose feature reads other apps' UI.
struct AccessibilityAccessSection: View {
    let insights: Insights

    var body: some View {
        Section {
            AccessibilityAccessRow(insights: insights)
        }
    }
}
