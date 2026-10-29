import SwiftUI

/// The Settings window: a dark-glass sidebar of searchable categories over an animated backdrop,
/// and one focused page of frosted cards per category.
struct SettingsView: View {
    private static let minimumSize = CGSize(width: 860, height: 600)
    private static let idealSize = CGSize(width: 1100, height: 760)
    private static let sidebarWidth: CGFloat = 236

    @Bindable var settings: SettingsStore
    let language: AppLanguageSettings
    let services: ModuleServices
    let updater: UpdaterService

    @AppStorage(SettingsCategory.storageKey) private var storedCategory = SettingsCategory.defaultCategory.rawValue
    @State private var query = ""
    @State private var isVisible = false
    @Environment(\.appearsActive) private var appearsActive

    private var category: SettingsCategory {
        SettingsCategory.restored(from: storedCategory)
    }

    private var selection: Binding<SettingsCategory> {
        Binding(
            get: { category },
            set: { storedCategory = $0.rawValue }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: selection, query: $query)
                .frame(width: Self.sidebarWidth)
            SettingsDetailView(
                category: category,
                settings: settings,
                language: language,
                services: services,
                updater: updater
            )
            .id(category)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background { SettingsBackdrop(isActive: isVisible && appearsActive) }
        .background { SettingsWindowConfigurator(title: String(localized: category.title)) }
        .environment(\.colorScheme, .dark)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .frame(
            minWidth: Self.minimumSize.width,
            idealWidth: Self.idealSize.width,
            minHeight: Self.minimumSize.height,
            idealHeight: Self.idealSize.height
        )
    }
}

extension SettingsCategory {
    /// Icon tile color in the sidebar and the page header.
    var tint: Color {
        switch self {
        case .general, .shortcuts: .gray
        case .notch, .remoteSession: .indigo
        case .hud, .media: .pink
        case .alerts, .notifications: .red
        case .shelf, .notes: .orange
        case .timer, .automations: .purple
        case .calendar, .unread: .blue
        case .weather, .network: .cyan
        case .battery, .meeting: .green
        case .headphones, .integrations: .teal
        case .performance, .timeTracking: .mint
        case .devOps, .profiles: .brown
        }
    }
}
