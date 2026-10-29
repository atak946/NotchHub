import AppKit
import SwiftUI

/// Settings for the Profiles feature: "Client Profiles" and "Remote Session Awareness" sections.
struct ProfilesSettingsSection: View {
    let profiles: Profiles
    @State private var editing: ClientProfile?

    init(profiles: Profiles) {
        self.profiles = profiles
    }

    var body: some View {
        Group {
            ClientProfilesSection(service: profiles.service, editing: $editing)
            RemoteSessionSettingsSection(store: profiles.store, monitor: profiles.remoteMonitor)
        }
        .sheet(item: $editing) { profile in
            ProfileEditorView(profile: profile, validator: ProfileStepValidator()) { saved in
                profiles.store.save(saved)
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
    }
}

private struct ClientProfilesSection: View {
    let service: ProfilesService
    @Binding var editing: ClientProfile?

    private var store: ProfilesStore { service.store }

    var body: some View {
        @Bindable var store = store
        Section("Müşteri Profilleri") {
            if store.profiles.isEmpty {
                Text("Henüz profil yok. Bir profil ekleyin veya aşağıdan bir çalışma klasöründen oluşturun.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.profiles) { profile in
                profileRow(profile)
            }
            .onMove { store.move(fromOffsets: $0, toOffset: $1) }

            Button("Profil Ekle", systemImage: "plus") {
                editing = ClientProfile(name: "", color: ProfileColor.allCases[store.profiles.count % ProfileColor.allCases.count])
            }
            Toggle("Çentikte profil uyarıları", isOn: $store.alertsEnabled)
            TextField("Terminal uygulaması bundle ID", text: $store.terminalBundleID)
            ProfilesVPNClientPicker(store: store)
            WorkspaceSuggestionsView(service: service)
        }
    }

    private func profileRow(_ profile: ClientProfile) -> some View {
        HStack(spacing: 8) {
            Circle().fill(profile.color.color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName)
                Text(rowSubtitle(profile))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if service.isRunning(profile.id) {
                ProgressView().controlSize(.small)
                Button("İptal") { service.cancel() }
            } else {
                Button("Çalıştır") { service.activate(profile.id) }
                    .disabled(service.isRunning)
            }
            Button("Düzenle") { editing = profile }
            Button(role: .destructive) {
                store.delete(id: profile.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Profili sil")
        }
    }

    private func rowSubtitle(_ profile: ClientProfile) -> String {
        var parts = ["\(profile.steps.count) adım"]
        if store.activeProfileID == profile.id { parts.append("etkin") }
        if let report = service.lastReports[profile.id], let failure = report.firstFailure {
            parts.append("son çalıştırma: \(failure.summary) – \(ProfilesService.message(of: failure.status))")
        }
        return parts.joined(separator: " · ")
    }
}

private struct WorkspaceSuggestionsView: View {
    let service: ProfilesService

    var body: some View {
        @Bindable var store = service.store
        DisclosureGroup("Çalışma klasöründen öneriler") {
            HStack {
                TextField("Çalışma klasörü", text: $store.workspaceRoot)
                Button("Seç…") {
                    if let path = ProfilesFolderPicker.pick(startingAt: store.workspaceRoot) { store.workspaceRoot = path }
                }
                Button(service.isScanning ? "Taranıyor…" : "Tara") {
                    Task { await service.scanWorkspace() }
                }
                .disabled(service.isScanning)
            }
            if service.suggestions.isEmpty {
                Text("Compose dosyası, .sln veya package.json içeren klasörleri bulur (2 seviye derinlik).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(service.suggestions) { suggestion in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(suggestion.name)
                        Text(suggestion.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer()
                    ForEach(suggestion.sortedKinds, id: \.self) { kind in
                        Text(kind.title)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                    }
                    Button("Profil Oluştur") { service.createProfile(from: suggestion) }
                }
            }
        }
    }
}

private struct RemoteSessionSettingsSection: View {
    @Bindable var store: ProfilesStore
    let monitor: RemoteSessionMonitor

    var body: some View {
        Section("Uzak Oturum Farkındalığı") {
            Toggle("Biri bu Mac'e bağlandığında göster", isOn: $store.remoteMonitorEnabled)
            Toggle("Oturum başlayıp bittiğinde uyar", isOn: $store.remoteAlertsEnabled)
                .disabled(!store.remoteMonitorEnabled)
            LabeledContent("Durum", value: statusText)
            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        guard store.remoteMonitorEnabled else { return "Kapalı" }
        if monitor.isSessionActive {
            return "Etkin: " + monitor.activeSources.map(\.title).joined(separator: ", ")
        }
        return "Oturum algılanmadı"
    }

    private var explanation: String {
        var text = "Sezgisel, 5 sn'de bir kontrol edilir: AnyDesk, boşta röle bağlantısından (veya 7070 portundan) fazla TCP bağlantısı tuttuğunda bağlı sayılır; "
            + "Ekran Paylaşımı / Uzaktan Yönetim ise servisleri "
            + "kurulmuş bağlantılara sahip olduğunda sayılır. Oturumları kaçırabilir veya yanlış bildirebilir."
        if monitor.assessment.isDegraded {
            let names = monitor.assessment.uninspectableSources.sorted().map(\.title).joined(separator: ", ")
            text += " Sınırlı mod: \(names) bağlantıları root olmadan okunamaz, bu yüzden yalnızca çalışan işlem algılanır."
        }
        if monitor.isSessionOnConsole == false {
            text += " Bu oturum konsolda değil."
        }
        return text
    }
}

enum ProfilesFolderPicker {
    @MainActor
    static func pick(startingAt path: String?) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Seç"
        if let path, !path.isEmpty {
            panel.directoryURL = URL(filePath: path, directoryHint: .isDirectory)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path(percentEncoded: false)
    }
}
