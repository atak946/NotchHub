import SwiftUI

/// Both Profiles tiles for the Status grid. Inside a grid the `Group` children become separate cells.
struct ProfilesStatusTiles: View {
    let profiles: Profiles

    init(profiles: Profiles) {
        self.profiles = profiles
    }

    var body: some View {
        Group {
            ProfilesStatusTile(service: profiles.service)
            if profiles.store.remoteMonitorEnabled {
                RemoteSessionStatusTile(monitor: profiles.remoteMonitor)
            }
        }
    }
}

/// ~140 × 70 tile: active profile (dot + name), run progress, primary action = run / cancel, menu = pick profile.
struct ProfilesStatusTile: View {
    let service: ProfilesService
    @State private var isHovered = false

    init(service: ProfilesService) {
        self.service = service
    }

    private var store: ProfilesStore { service.store }

    private var focusedProfile: ClientProfile? {
        if let runState = service.runState { return store.profile(id: runState.profileID) }
        return store.activeProfile ?? store.profiles.first
    }

    var body: some View {
        let tint = focusedProfile?.color.color ?? .gray
        Menu {
            menuContent
        } label: {
            label(tint: tint)
        } primaryAction: {
            primaryAction()
        }
        .menuStyle(.button)
        .buttonStyle(ProfilesPressableStyle())
        .menuIndicator(.hidden)
        .profilesTile(tint: tint, isHovered: isHovered)
        .onHover { isHovered = $0 }
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private func label(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text("Profil")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                actionGlyph
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(store.activeProfile == nil && service.runState == nil ? Color.primary.opacity(0.25) : tint)
                    .frame(width: ProfilesMetrics.dotSize, height: ProfilesMetrics.dotSize)
                Text(focusedProfile?.displayName ?? "Profil yok")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            Text(stateText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .monospacedDigit()
        }
    }

    @ViewBuilder private var actionGlyph: some View {
        if service.isRunning {
            ProgressView().controlSize(.mini)
        } else {
            Image(systemName: "play.fill")
                .font(.system(size: 10, weight: .bold))
                .opacity(focusedProfile == nil ? 0.3 : (isHovered ? 1 : 0.7))
        }
    }

    @ViewBuilder private var menuContent: some View {
        if service.isRunning {
            Button("Çalışmayı iptal et", systemImage: "xmark.circle") { service.cancel() }
        } else {
            ForEach(store.profiles) { profile in
                Button(profile.displayName) { service.activate(profile.id) }
            }
            if let active = store.activeProfile, !active.deactivateSteps.isEmpty {
                Divider()
                Button("\(active.displayName) devre dışı bırak", systemImage: "stop.circle") { service.deactivate(active.id) }
            }
        }
    }

    private var stateText: String {
        if let runState = service.runState {
            return "\(runState.progressText) · \(runState.stepSummary)"
        }
        if store.activeProfile != nil { return "Etkin" }
        return store.profiles.isEmpty ? "Ayarlar'dan ekleyin" : "Etkin değil · çalıştırmak için tıklayın"
    }

    private var helpText: String {
        if service.isRunning { return "Profil çalışıyor – iptal için tıklayın" }
        guard let focusedProfile else { return "Henüz müşteri profili yok" }
        return "\(focusedProfile.displayName) çalıştır"
    }

    private func primaryAction() {
        if service.isRunning {
            service.cancel()
        } else if let focusedProfile {
            service.activate(focusedProfile.id)
        }
    }
}

/// ~140 × 70 tile: remote-session heuristic state with an explicit "heuristic" label.
struct RemoteSessionStatusTile: View {
    let monitor: RemoteSessionMonitor
    @State private var isHovered = false

    init(monitor: RemoteSessionMonitor) {
        self.monitor = monitor
    }

    var body: some View {
        let tint: Color = monitor.isSessionActive ? .red : .green
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: monitor.isSessionActive ? "eye.fill" : "eye.slash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, isActive: monitor.isSessionActive)
                Text("Uzak · sezgisel")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(monitor.isSessionActive ? "Oturum etkin" : "Oturum yok")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(detailText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .profilesTile(tint: tint, isHovered: isHovered)
        .onHover { isHovered = $0 }
        .help(helpText)
        .accessibilityElement(children: .combine)
    }

    private var detailText: String {
        if monitor.isSessionActive {
            return monitor.activeSources.map(\.title).joined(separator: ", ")
        }
        if monitor.assessment.isDegraded { return "Sınırlı: yalnızca işlem" }
        return monitor.assessment.runningSources.isEmpty ? "Çalışan uzak uygulama yok" : "İzleniyor"
    }

    private var helpText: String {
        var text = "Sezgisel: AnyDesk, Ekran Paylaşımı ve Uzaktan Yönetim'in kurulmuş bağlantılarını arar."
        if monitor.assessment.isDegraded {
            let names = monitor.assessment.uninspectableSources.sorted().map(\.title).joined(separator: ", ")
            text += " \(names) soketleri root olmadan okunamaz; işlem algılama kullanılıyor."
        }
        return text
    }
}
