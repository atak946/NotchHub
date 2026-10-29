import SwiftUI

/// One settings page: a compact header and the page's sections rendered as glass cards.
/// Search terms for each page live in SettingsSearchCatalog+Entries.swift; keep them in sync.
struct SettingsDetailView: View {
    private static let maxContentWidth: CGFloat = 680

    let category: SettingsCategory
    @Bindable var settings: SettingsStore
    let language: AppLanguageSettings
    let services: ModuleServices
    let updater: UpdaterService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsTheme.Spacing.l + 2) {
                GlassPageHeader(
                    title: category.title,
                    subtitle: category.subtitle,
                    symbol: category.systemImage,
                    tint: category.tint
                )
                Form { page }
                    .formStyle(GlassFormStyle())
            }
            .frame(maxWidth: Self.maxContentWidth, alignment: .leading)
            .padding(.horizontal, SettingsTheme.Spacing.xl + 4)
            .padding(.top, SettingsTheme.Spacing.titleBar + SettingsTheme.Spacing.s)
            .padding(.bottom, SettingsTheme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.automatic)
    }

    @ViewBuilder
    private var page: some View {
        switch category {
        case .general, .notch, .hud, .alerts:
            appPage
        case .shelf, .media, .timer, .calendar, .notes, .weather, .battery:
            modulePage
        case .notifications, .unread, .meeting:
            communicationPage
        case .network, .headphones, .performance, .remoteSession:
            systemPage
        case .devOps, .profiles, .integrations, .shortcuts, .automations, .timeTracking:
            developerPage
        }
    }

    @ViewBuilder
    private var appPage: some View {
        switch category {
        case .general: GeneralSettingsPage(settings: settings, language: language, updater: updater)
        case .notch: NotchAppearanceSettingsPage(settings: settings)
        case .hud: SystemHUDSettingsSection(hud: services.hud)
        default: NotchAlertsSettingsSection(settings: settings)
        }
    }

    @ViewBuilder
    private var modulePage: some View {
        switch category {
        case .shelf:
            ShelfSettingsSection(store: services.shelf)
            ClipboardSettingsSection(history: services.clipboard)
        case .media: MediaSettingsSection(settings: settings)
        case .timer: TimerSettingsSection(timer: services.timer)
        case .calendar: CalendarSettingsSection(calendar: services.calendar)
        case .notes: NotesSettingsSection(store: services.notes, calculator: services.calculator)
        case .weather: WeatherSettingsSection(weather: services.weather)
        default: ChargingSettingsSection(charging: services.charging)
        }
    }

    @ViewBuilder
    private var communicationPage: some View {
        let insights = services.insights
        let system = services.system
        switch category {
        case .notifications:
            AccessibilityAccessSection(insights: insights)
            NotificationMirrorSettingsSection(mirror: insights.mirror)
        case .unread:
            AccessibilityAccessSection(insights: insights)
            UnreadSettingsSection(monitor: insights.unread)
        default:
            MeetingModeSettingsSection(controller: system.meetingMode)
            CameraMirrorSettingsSection(reminder: services.cameraMirror.reminder)
            MicMuteSettingsSection(controller: system.micMute)
            MicCameraSettingsSection(monitor: system.micCamera)
        }
    }

    @ViewBuilder
    private var systemPage: some View {
        let system = services.system
        switch category {
        case .network:
            NetworkSettingsSection(monitor: system.network)
            VPNSettingsSection(monitor: system.vpn)
        case .headphones: HeadphoneBatterySettingsSection(monitor: system.headphones)
        case .performance: SystemPressureSettingsSection(monitor: system.pressure)
        default: RemoteSessionSettingsSection(store: services.profiles.store, monitor: services.profiles.remoteMonitor)
        }
    }

    @ViewBuilder
    private var developerPage: some View {
        switch category {
        case .devOps: DevOpsSettingsSection(monitors: services.devOps)
        case .profiles: ProfilesSettingsSection(profiles: services.profiles)
        case .integrations: IntegrationsSettingsSection(service: services.externalAlerts)
        case .shortcuts: ShortcutsSettingsPage()
        case .automations: AutomationsSettingsSection(automations: services.automations)
        default:
            AccessibilityAccessSection(insights: services.insights)
            TimeTrackingSettingsSection(tracker: services.insights.timeTracker)
        }
    }
}
