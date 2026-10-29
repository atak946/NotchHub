import SwiftUI

/// Picks the VPN client the "VPN bekle" step opens: installed known clients, or the first one automatically.
struct ProfilesVPNClientPicker: View {
    @Bindable var store: ProfilesStore
    @State private var installed: [VPNInstalledClient] = []

    var body: some View {
        Picker("VPN uygulaması", selection: $store.vpnAppBundleID) {
            Text(automaticTitle).tag(String?.none)
            ForEach(installed, id: \.bundleIdentifier) { entry in
                Text(entry.displayName).tag(String?.some(entry.bundleIdentifier))
            }
            if let custom = customSelection {
                Text(VPNClientCatalog.client(bundleIdentifier: custom)?.displayName ?? custom)
                    .tag(String?.some(custom))
            }
        }
        .help("Tünel yokken “VPN bekle” adımı tarafından açılır.")
        .onAppear { installed = store.availableVPNClients() }
    }

    private var automaticTitle: String {
        guard let first = installed.first else { return String(localized: "Otomatik (yüklü istemci yok)") }
        return String(localized: "Otomatik (\(first.displayName))")
    }

    /// A stored choice that is not installed (or was typed in an earlier version) stays selectable.
    private var customSelection: String? {
        guard let selected = store.vpnAppBundleID,
              !installed.contains(where: { $0.bundleIdentifier == selected })
        else { return nil }
        return selected
    }
}
