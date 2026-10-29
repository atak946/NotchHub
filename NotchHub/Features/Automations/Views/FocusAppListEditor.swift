import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Distraction list rows (icon, name, bundle ID, on/off, remove) plus an "Add App" menu.
struct FocusAppListEditor: View {
    let service: FocusGuardService

    var body: some View {
        ForEach(service.apps) { app in
            HStack(spacing: 8) {
                FocusAppIcon(bundleID: app.bundleID)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                    Text(app.bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("\(app.name) izle", isOn: enabledBinding(app))
                    .labelsHidden()
                Button {
                    service.removeApp(app.id)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("\(app.name) kaldır")
            }
        }
        HStack {
            Menu("Uygulama Ekle") {
                ForEach(FocusAppCatalog.runningApps(excluding: Set(service.apps.map(\.id)))) { app in
                    Button(app.name) { service.addApp(app) }
                }
                Divider()
                Button("Uygulamalar'dan seç…") { chooseApp() }
            }
            .fixedSize()
            Spacer()
            Button("Varsayılanları Geri Yükle") { service.resetApps() }
        }
    }

    private func enabledBinding(_ app: FocusApp) -> Binding<Bool> {
        Binding(
            get: { service.apps.first { $0.id == app.id }?.isEnabled ?? false },
            set: { service.setApp(app.id, enabled: $0) }
        )
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.prompt = "Ekle"
        guard panel.runModal() == .OK else { return }
        panel.urls.compactMap(FocusAppCatalog.app(at:)).forEach(service.addApp)
    }
}

/// Small app icon looked up by bundle ID.
struct FocusAppIcon: View {
    static let side: CGFloat = 20

    let bundleID: String

    var body: some View {
        Group {
            if let icon = FocusAppCatalog.icon(for: bundleID) {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.side, height: Self.side)
    }
}

/// Running / installed app lookups for the list editor.
@MainActor
enum FocusAppCatalog {
    static func runningApps(excluding ids: Set<String>) -> [FocusApp] {
        let ownID = Bundle.main.bundleIdentifier?.lowercased()
        var seen = ids
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> FocusApp? in
                guard let bundleID = app.bundleIdentifier, bundleID.lowercased() != ownID else { return nil }
                return FocusApp(bundleID: bundleID, name: app.localizedName ?? bundleID)
            }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func app(at url: URL) -> FocusApp? {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return nil }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return FocusApp(bundleID: bundleID, name: name)
    }

    static func icon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
