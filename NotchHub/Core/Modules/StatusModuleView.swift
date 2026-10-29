import SwiftUI

/// "Status" tab: client profile launcher plus a scrolling grid of monitor tiles.
struct StatusModuleView: View {
    let services: ModuleServices

    private static let tileWidth: CGFloat = 140
    private static let spacing: CGFloat = 8
    private let columns = [GridItem(.adaptive(minimum: tileWidth, maximum: tileWidth + 8), spacing: spacing)]

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Self.spacing) {
                ProfilesQuickLauncher(profiles: services.profiles)
                LazyVGrid(columns: columns, alignment: .leading, spacing: Self.spacing) {
                    SystemStatusTiles(monitors: services.system)
                    DevOpsStatusTiles(monitors: services.devOps)
                    ProfilesStatusTiles(profiles: services.profiles)
                    AutomationsStatusTiles(automations: services.automations)
                    InsightsStatusTiles(insights: services.insights)
                    IntegrationsStatusTile(service: services.externalAlerts)
                }
            }
        }
        .scrollIndicators(.never)
    }
}

/// Small glyphs beside the notch while the panel is closed (mic, VPN, docker, unread, remote session…).
struct StatusCompactIndicators: View {
    let services: ModuleServices

    var body: some View {
        HStack(spacing: 4) {
            SystemCompactIndicators(monitors: services.system)
            DevOpsCompactIndicators(monitors: services.devOps)
            InsightsCompactIndicators(insights: services.insights)
            ProfilesCompactIndicators(profiles: services.profiles)
        }
        .fixedSize()
    }
}
