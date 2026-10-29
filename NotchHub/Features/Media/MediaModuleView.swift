import SwiftUI

/// Expanded media panel: artwork, track info, transport controls, seek bar and output switcher (~590 × 160 pt).
struct MediaModuleView: View {
    let media: MediaService
    let audio: AudioOutputService

    private static let artworkSize: CGFloat = 116
    private static let artworkRadius: CGFloat = 14
    private static let progressTick: TimeInterval = 0.5

    init(media: MediaService, audio: AudioOutputService) {
        self.media = media
        self.audio = audio
    }

    var body: some View {
        Group {
            if let track = media.nowPlaying {
                playerView(track)
            } else {
                MediaEmptyView(deniedSources: media.permissionDeniedSources, audio: audio)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: media.nowPlaying?.trackID)
    }

    private func playerView(_ track: NowPlaying) -> some View {
        HStack(alignment: .center, spacing: 18) {
            artwork
            VStack(alignment: .leading, spacing: 0) {
                header(track)
                Spacer(minLength: 6)
                TimelineView(.periodic(from: .now, by: Self.progressTick)) { context in
                    MediaProgressBar(
                        position: media.position(at: context.date),
                        duration: track.duration,
                        onSeek: media.seek(to:)
                    )
                }
                Spacer(minLength: 4)
                controls(track)
            }
            .frame(maxHeight: Self.artworkSize)
        }
        .padding(.horizontal, 4)
    }

    private var artwork: some View {
        MediaArtworkView(image: media.artwork, cornerRadius: Self.artworkRadius)
            .frame(width: Self.artworkSize, height: Self.artworkSize)
            .background {
                if let image = media.artwork {
                    Image(nsImage: image)
                        .resizable()
                        .blur(radius: 18)
                        .opacity(0.45)
                        .offset(y: 6)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            .scaleEffect(media.nowPlaying?.isPlaying == true ? 1 : 0.94)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: media.nowPlaying?.isPlaying)
    }

    private func header(_ track: NowPlaying) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(track.artist.isEmpty ? track.album : track.artist)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(track.source.displayName)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: .capsule)
        }
        .help("\(track.title) — \(track.artist)")
    }

    private func controls(_ track: NowPlaying) -> some View {
        HStack(spacing: 6) {
            MediaIconButton(systemImage: "backward.fill", help: "Önceki", action: media.previous)
            MediaIconButton(
                systemImage: track.isPlaying ? "pause.fill" : "play.fill",
                help: track.isPlaying ? "Duraklat" : "Oynat",
                size: 20,
                diameter: 38,
                action: media.playPause
            )
            MediaIconButton(systemImage: "forward.fill", help: "Sonraki", action: media.next)
            Spacer(minLength: 0)
            if track.isPlaying {
                MediaEqualizerView(isPlaying: track.isPlaying)
                    .frame(width: 16, height: 12)
                    .foregroundStyle(.secondary)
            }
            AudioOutputMenu(audio: audio)
        }
    }
}

/// Shown when no player has a track loaded.
private struct MediaEmptyView: View {
    let deniedSources: Set<MediaSource>
    let audio: AudioOutputService

    private static let automationSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    )

    private var subtitle: String {
        let denied = MediaSource.allCases.filter(deniedSources.contains).map(\.displayName)
        guard !denied.isEmpty else { return "Burada denetlemek için Spotify veya Music'te müzik başlat." }
        return "NotchHub'ın \(denied.joined(separator: " ve ")) uygulamasını denetlemesine Otomasyon ayarlarından izin ver."
    }

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary)
                Image(systemName: "music.note")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Çalan bir şey yok")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    ForEach(MediaSource.allCases) { source in
                        OpenPlayerButton(source: source)
                    }
                    if !deniedSources.isEmpty, let url = Self.automationSettingsURL {
                        Link("Ayarları Aç", destination: url)
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
            }
            Spacer(minLength: 0)
            AudioOutputMenu(audio: audio)
        }
        .padding(.horizontal, 8)
    }
}

private struct OpenPlayerButton: View {
    let source: MediaSource

    @State private var isHovered = false

    var body: some View {
        let isInstalled = MediaAppLauncher.isInstalled(source)
        Button {
            MediaAppLauncher.open(source)
        } label: {
            Text("\(source.displayName) aç")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(isHovered ? 1 : 0.6), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(PressScaleButtonStyle())
        .foregroundStyle(.primary)
        .disabled(!isInstalled)
        .opacity(isInstalled ? 1 : 0.4)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help(isInstalled ? "\(source.displayName) aç" : "\(source.displayName) yüklü değil")
    }
}
