import OSLog
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let services: ModuleServices
    let updater: UpdaterService

    private static let windowSize = CGSize(width: 560, height: 640)

    var body: some View {
        TabView {
            Tab("Genel", systemImage: "gearshape") {
                GeneralSettingsTab(settings: settings, updater: updater)
            }
            Tab("Modüller", systemImage: "square.grid.2x2") {
                ModulesSettingsTab(settings: settings, services: services)
            }
            Tab("Takvim", systemImage: "calendar") {
                SettingsForm {
                    CalendarSettingsSection(calendar: services.calendar)
                    CameraMirrorSettingsSection(reminder: services.cameraMirror.reminder)
                }
            }
            Tab("İzleyiciler", systemImage: "gauge.with.dots.needle.67percent") {
                SettingsForm {
                    SystemSettingsSection(monitors: services.system)
                    DevOpsSettingsSection(monitors: services.devOps)
                    AutomationsSettingsSection(automations: services.automations)
                    InsightsSettingsSection(insights: services.insights)
                }
            }
            Tab("İş Akışı", systemImage: "briefcase") {
                SettingsForm {
                    ProfilesSettingsSection(profiles: services.profiles)
                    IntegrationsSettingsSection(service: services.externalAlerts)
                }
            }
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
    }
}

private struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
    }
}

private struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore
    let updater: UpdaterService
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Settings")

    var body: some View {
        SettingsForm {
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
                LabeledContent("Paneli aç/kapat", value: "⌥⌘N")
            }

            Section("Davranış") {
                LabeledContent("Üzerine gelme gecikmesi") {
                    HStack {
                        Slider(value: $settings.hoverDelay, in: SettingsStore.hoverDelayRange, step: 0.05)
                            .frame(width: 180)
                        Text("\(Int(settings.hoverDelay * 1000)) ms")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                Toggle("Uygulama tam ekranken gizle", isOn: $settings.hideInFullScreen)
                Toggle("Kapalıyken medya kontrolleri", isOn: $settings.showsCompactMediaControls)
            }

            Section("Çentik Uyarıları") {
                Toggle("Çentikten animasyonlu uyarılar", isOn: $settings.alertsEnabled)
                Toggle("Parça değişimlerini göster", isOn: $settings.showTrackChangeAlerts)
                    .disabled(!settings.alertsEnabled)
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

            UpdatesSettingsSection(updater: updater)
            SupportSettingsSection()
        }
    }

    private func updateLaunchAtLogin(_ isEnabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(isEnabled)
            launchAtLoginError = nil
        } catch {
            logger.error("Launch at login update failed: \(error.localizedDescription)")
            launchAtLoginError = "Giriş öğesi güncellenemedi: \(error.localizedDescription)"
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

private struct ModulesSettingsTab: View {
    let settings: SettingsStore
    let services: ModuleServices

    var body: some View {
        SettingsForm {
            Section("Panel Sekmeleri") {
                ForEach(NotchModule.allCases) { module in
                    Toggle(isOn: moduleBinding(module)) {
                        Label(module.title, systemImage: module.systemImage)
                    }
                }
            }
            SystemHUDSettingsSection(hud: services.hud)
            ShelfSettingsSection(store: services.shelf)
            ClipboardSettingsSection(history: services.clipboard)
            TimerSettingsSection(timer: services.timer)
            NotesSettingsSection(store: services.notes)
        }
    }

    private func moduleBinding(_ module: NotchModule) -> Binding<Bool> {
        Binding(
            get: { settings.isEnabled(module) },
            set: { settings.setModule(module, enabled: $0) }
        )
    }
}
