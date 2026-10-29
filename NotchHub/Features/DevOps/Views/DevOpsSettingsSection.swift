import SwiftUI

/// Settings form sections for Docker, endpoints and local LLM monitoring.
struct DevOpsSettingsSection: View {
    let monitors: DevOpsMonitors

    init(monitors: DevOpsMonitors) {
        self.monitors = monitors
    }

    var body: some View {
        DockerSettingsSection(docker: monitors.docker)
        EndpointSettingsSection(endpoints: monitors.endpoints)
        LocalLLMSettingsSection(localLLM: monitors.localLLM)
    }
}

struct DockerSettingsSection: View {
    @Bindable private var docker: DockerMonitor

    init(docker: DockerMonitor) {
        self.docker = docker
    }

    var body: some View {
        Section("Docker") {
            Toggle("Container'ları izle", isOn: $docker.isEnabled)
            Toggle("Çökme, OOM ve sağlık değişikliklerinde uyar", isOn: $docker.alertsEnabled)
                .disabled(!docker.isEnabled)
            Toggle("docker stop kaynaklı çıkışları yoksay", isOn: $docker.ignoreStopExits)
                .disabled(!docker.isEnabled)
            LabeledContent("Daemon") {
                Text(docker.socketPath.map { "\(docker.daemonState.title) · \($0)" } ?? docker.daemonState.title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text("OrbStack, Docker Desktop ve colima soketlerini destekler.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct EndpointSettingsSection: View {
    @Bindable private var endpoints: EndpointMonitor
    @State private var draft: MonitoredEndpoint?

    init(endpoints: EndpointMonitor) {
        self.endpoints = endpoints
    }

    var body: some View {
        Section("Uç Noktalar") {
            Toggle("Uç noktaları izle", isOn: $endpoints.isEnabled)
            Toggle("Uç nokta kapanınca veya düzelince uyar", isOn: $endpoints.alertsEnabled)
                .disabled(!endpoints.isEnabled)
            if endpoints.endpoints.isEmpty {
                Text("Henüz uç nokta yok. Staging, localhost veya API sağlık URL'leri ekle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(endpoints.endpoints) { endpoint in
                EndpointRow(endpoint: endpoint, status: endpoints.status(for: endpoint.id)) {
                    draft = endpoint
                } onDelete: {
                    endpoints.remove(id: endpoint.id)
                }
            }
            Button("Uç Nokta Ekle…", systemImage: "plus") {
                draft = MonitoredEndpoint()
            }
        }
        .sheet(item: $draft) { endpoint in
            EndpointEditorView(
                endpoint: endpoint,
                isNew: !endpoints.endpoints.contains { $0.id == endpoint.id }
            ) { saved in
                endpoints.update(saved)
            }
        }
    }
}

private struct EndpointRow: View {
    let endpoint: MonitoredEndpoint
    let status: EndpointStatus
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(EndpointStatusTile.tint(for: status.state))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(endpoint.displayName)
                    if endpoint.requiresVPN {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.secondary)
                            .help("VPN gerekli")
                    }
                }
                Text(endpoint.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button("Düzenle", systemImage: "pencil", action: onEdit)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            Button("Kaldır", systemImage: "trash", role: .destructive, action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }

    private var summary: String {
        if let latency = status.latency, status.state == .up || status.state == .degraded {
            return "\(Int((latency * 1000).rounded())) ms"
        }
        return status.lastError ?? status.state.title
    }
}

/// Sheet for adding or editing one endpoint, with inline validation.
struct EndpointEditorView: View {
    @State private var endpoint: MonitoredEndpoint
    @Environment(\.dismiss) private var dismiss

    private let isNew: Bool
    private let onSave: (MonitoredEndpoint) -> Void

    init(endpoint: MonitoredEndpoint, isNew: Bool, onSave: @escaping (MonitoredEndpoint) -> Void) {
        _endpoint = State(initialValue: endpoint)
        self.isNew = isNew
        self.onSave = onSave
    }

    private var errors: [EndpointValidationError] {
        EndpointValidator.validate(endpoint)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Uç Nokta Ekle" : "Uç Nokta Düzenle")
                .font(.headline)
            Form {
                TextField("Ad", text: $endpoint.name, prompt: Text("Staging API"))
                TextField("URL", text: $endpoint.url, prompt: Text("https://staging.example.com/health"))
                Picker("Yöntem", selection: $endpoint.method) {
                    ForEach(MonitoredEndpoint.Method.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                Picker("Aralık", selection: $endpoint.intervalSeconds) {
                    ForEach(intervalOptions, id: \.self) { seconds in
                        Text(Self.intervalTitle(seconds)).tag(seconds)
                    }
                }
                LabeledContent("Beklenen durum") {
                    HStack(spacing: 4) {
                        TextField("Başlangıç", value: $endpoint.expectedStatusLower, format: .number.grouping(.never))
                            .frame(width: 56)
                        Text("–")
                        TextField("Bitiş", value: $endpoint.expectedStatusUpper, format: .number.grouping(.never))
                            .frame(width: 56)
                    }
                    .labelsHidden()
                }
                Toggle("VPN gerekli", isOn: $endpoint.requiresVPN)
            }
            .formStyle(.grouped)

            ForEach(errors, id: \.self) { error in
                Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("İptal", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Ekle" : "Kaydet") {
                    onSave(endpoint)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!errors.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var intervalOptions: [Int] {
        let options = MonitoredEndpoint.intervalOptions
        return options.contains(endpoint.intervalSeconds) ? options : (options + [endpoint.intervalSeconds]).sorted()
    }

    private static func intervalTitle(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) saniye" : "\(seconds / 60) dk\(seconds % 60 == 0 ? "" : " \(seconds % 60) sn")"
    }
}

struct LocalLLMSettingsSection: View {
    @Bindable private var localLLM: LocalLLMMonitor

    init(localLLM: LocalLLMMonitor) {
        self.localLLM = localLLM
    }

    var body: some View {
        Section("Yerel LLM") {
            Toggle("LM Studio ve Ollama'yı izle", isOn: $localLLM.isEnabled)
            Toggle("Sunucu başlayınca veya durunca uyar", isOn: $localLLM.alertsEnabled)
                .disabled(!localLLM.isEnabled)
            portField("LM Studio portu", value: $localLLM.lmStudioPort)
            portField("Ollama portu", value: $localLLM.ollamaPort)
        }
    }

    private func portField(_ title: String, value: Binding<Int>) -> some View {
        LabeledContent(title) {
            TextField(title, value: value, format: .number.grouping(.never))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
        .disabled(!localLLM.isEnabled)
    }
}
