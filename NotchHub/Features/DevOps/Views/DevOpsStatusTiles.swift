import SwiftUI

/// Docker tile: running/total, unhealthy count and daemon state.
struct DockerStatusTile: View {
    let docker: DockerMonitor

    init(docker: DockerMonitor) {
        self.docker = docker
    }

    var body: some View {
        DevOpsTileChrome(systemImage: "shippingbox.fill", title: "Docker", value: value, detail: detail, tint: tint)
    }

    private var value: String {
        guard docker.isRunning else { return docker.daemonState.title }
        return String(localized: "\(docker.counts.running)/\(docker.counts.total) çalışıyor")
    }

    private var detail: String? {
        guard docker.isEnabled else { return String(localized: "İzleme kapalı") }
        guard docker.isRunning else { return docker.socketPath.map { ($0 as NSString).lastPathComponent } }
        if docker.counts.unhealthy > 0 { return String(localized: "\(docker.counts.unhealthy) sağlıksız") }
        if docker.hasRecentFailure, let failure = docker.lastFailure { return String(localized: "\(failure.containerName) başarısız") }
        return String(localized: "Hepsi sağlıklı")
    }

    private var tint: Color {
        guard docker.isEnabled, docker.isRunning else { return .gray }
        if docker.hasRecentFailure { return .red }
        if docker.counts.unhealthy > 0 { return .orange }
        return .green
    }
}

/// Endpoints tile: how many are up and the worst one. Click re-checks all.
struct EndpointStatusTile: View {
    let endpoints: EndpointMonitor

    init(endpoints: EndpointMonitor) {
        self.endpoints = endpoints
    }

    var body: some View {
        DevOpsTileChrome(
            systemImage: "network",
            title: String(localized: "Uç Noktalar"),
            value: value,
            detail: detail,
            tint: Self.tint(for: endpoints.overallState),
            action: endpoints.endpoints.isEmpty ? nil : { endpoints.checkAllNow() }
        )
        .help("Tüm uç noktaları şimdi denetlemek için tıkla")
    }

    private var value: String {
        guard endpoints.isEnabled else { return String(localized: "Kapalı") }
        guard !endpoints.endpoints.isEmpty else { return String(localized: "Yok") }
        let up = endpoints.endpoints.filter {
            let state = endpoints.status(for: $0.id).state
            return state == .up || state == .degraded
        }.count
        return String(localized: "\(up)/\(endpoints.endpoints.count) ayakta")
    }

    private var detail: String? {
        guard endpoints.isEnabled else { return String(localized: "İzleme kapalı") }
        guard !endpoints.endpoints.isEmpty else { return String(localized: "Ayarlar'dan ekle") }
        if let down = endpoints.downEndpoints.first { return String(localized: "\(down.displayName) kapalı") }
        if let degraded = endpoints.endpoints.first(where: { endpoints.status(for: $0.id).state == .degraded }) {
            return String(localized: "\(degraded.displayName) yavaş")
        }
        if endpoints.overallState == .pausedVPNOff { return String(localized: "Duraklatıldı (VPN kapalı)") }
        return String(localized: "Hepsine ulaşılıyor")
    }

    static func tint(for state: EndpointHealthState) -> Color {
        switch state {
        case .up: .green
        case .degraded: .orange
        case .down: .red
        case .unknown, .pausedVPNOff: .gray
        }
    }
}

/// Local LLM tile: which server is up and the loaded model.
struct LocalLLMStatusTile: View {
    let localLLM: LocalLLMMonitor

    init(localLLM: LocalLLMMonitor) {
        self.localLLM = localLLM
    }

    var body: some View {
        DevOpsTileChrome(
            systemImage: "cpu",
            title: String(localized: "Yerel LLM"),
            value: localLLM.activeServer?.title ?? (localLLM.isEnabled ? String(localized: "Çevrimdışı") : String(localized: "Kapalı")),
            detail: detail,
            tint: localLLM.activeServer == nil ? .gray : .purple
        )
    }

    private var detail: String? {
        guard localLLM.isEnabled else { return String(localized: "İzleme kapalı") }
        guard let server = localLLM.activeServer else { return "LM Studio · Ollama" }
        let status = localLLM.status(for: server)
        if let model = status.loadedModels.first { return model }
        if let installed = status.installedModelCount { return String(localized: "\(installed) model, hiçbiri yüklü değil") }
        return String(localized: "Model yüklü değil")
    }
}

/// The three DevOps tiles, ready to drop into the Status grid (no container of its own).
struct DevOpsStatusTiles: View {
    let monitors: DevOpsMonitors

    init(monitors: DevOpsMonitors) {
        self.monitors = monitors
    }

    var body: some View {
        DockerStatusTile(docker: monitors.docker)
        EndpointStatusTile(endpoints: monitors.endpoints)
        LocalLLMStatusTile(localLLM: monitors.localLLM)
    }
}
