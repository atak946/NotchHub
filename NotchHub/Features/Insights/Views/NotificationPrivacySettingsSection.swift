import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// "Uygulama bazlı gizlilik": per-app override of the global "Mesaj içeriğini göster" toggle.
struct NotificationPrivacySettingsSection: View {
    let privacy: NotificationPrivacySettings
    let globalShowsText: Bool
    @State private var runningApps: [NotificationAppIdentity] = []

    var body: some View {
        Section("Uygulama bazlı gizlilik") {
            if privacy.listedApps.isEmpty {
                Text("Henüz yansıtılan bildirim yok. Bildirim gelen uygulamalar burada listelenir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(privacy.listedApps) { app in
                NotificationPrivacyAppRow(privacy: privacy, app: app)
            }
            Menu("Uygulama ekle") {
                ForEach(runningApps) { app in
                    Button(app.name) { privacy.recordSeen(app) }
                }
                if !runningApps.isEmpty { Divider() }
                Button("Uygulamalar klasöründen seç…", action: chooseApplication)
            }
            .onAppear { runningApps = NotificationPrivacyAppSource.runningApps() }
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footnote: String {
        let global = globalShowsText ? String(localized: "gösterilir") : String(localized: "gizlenir")
        return String(localized: "“Varsayılan” genel ayarı izler (şu an içerik \(global)). Gizlenen bildirimlerde çentikte yalnızca uygulama ve gönderici görünür; içeriği “Göster” ile açabilirsiniz.")
    }

    private func chooseApplication() {
        guard let app = NotificationPrivacyAppSource.chooseApplication() else { return }
        privacy.recordSeen(app)
    }
}

/// One app: icon, name and the three-way choice.
private struct NotificationPrivacyAppRow: View {
    private static let iconSize: CGFloat = 20

    let privacy: NotificationPrivacySettings
    let app: NotificationAppIdentity

    var body: some View {
        Picker(selection: selection) {
            ForEach(NotificationContentVisibility.allCases) { visibility in
                Text(visibility.title).tag(visibility)
            }
        } label: {
            HStack(spacing: 8) {
                icon
                Text(app.name)
                    .lineLimit(1)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = AppIconResolver.shared.icon(bundleID: app.bundleID, appName: app.name) {
            Image(nsImage: image)
                .resizable()
                .frame(width: Self.iconSize, height: Self.iconSize)
                .accessibilityHidden(true)
        } else {
            Image(systemName: MessagingApp.systemImage(for: app.name))
                .frame(width: Self.iconSize, height: Self.iconSize)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var selection: Binding<NotificationContentVisibility> {
        Binding(
            get: { privacy.visibility(for: app) },
            set: { privacy.setVisibility($0, for: app) }
        )
    }
}

/// Apps the user can add by hand: running regular apps or an `.app` picked with an open panel.
@MainActor
enum NotificationPrivacyAppSource {
    private static let applicationsDirectory = URL(filePath: "/Applications", directoryHint: .isDirectory)

    static func runningApps() -> [NotificationAppIdentity] {
        let ownBundleID = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != ownBundleID }
            .compactMap { app in
                app.localizedName.flatMap { NotificationAppIdentity(bundleID: app.bundleIdentifier, name: $0) }
            }
        var seen = Set<String>()
        return apps
            .filter { seen.insert($0.key).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func chooseApplication() -> NotificationAppIdentity? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = applicationsDirectory
        panel.prompt = String(localized: "Ekle")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return identity(ofApplicationAt: url)
    }

    static func identity(ofApplicationAt url: URL) -> NotificationAppIdentity? {
        let displayName = FileManager.default.displayName(atPath: url.path)
        let name = displayName.hasSuffix(".app") ? String(displayName.dropLast(".app".count)) : displayName
        return NotificationAppIdentity(bundleID: Bundle(url: url)?.bundleIdentifier, name: name)
    }
}
