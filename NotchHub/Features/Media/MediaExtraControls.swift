import SwiftUI

/// Icon button for an on/off player mode (shuffle, repeat, like, lyrics): tinted while on.
struct MediaToggleButton: View {
    let systemImage: String
    let help: LocalizedStringKey
    let isOn: Bool
    var activeTint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        MediaIconButton(systemImage: systemImage, help: help, size: 13, diameter: 26, action: action)
            .foregroundStyle(isOn ? AnyShapeStyle(activeTint) : AnyShapeStyle(.secondary))
            .symbolEffect(.bounce, value: isOn)
            .accessibilityValue(isOn ? Text("Açık") : Text("Kapalı"))
    }
}

/// The player's own volume: a speaker glyph that grows a slider on hover. Commits when the drag ends so each
/// gesture sends one script.
struct PlayerVolumeControl: View {
    let volume: Double
    let onChange: (Double) -> Void

    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var dragVolume: Double?

    private static let sliderWidth: CGFloat = 64
    private static let trackHeight: CGFloat = 4
    private static let hitHeight: CGFloat = 18
    private static let collapseDelay: Duration = .milliseconds(600)
    private static let expandAnimation = Animation.spring(response: 0.3, dampingFraction: 0.85)

    private var displayed: Double { dragVolume ?? volume }
    private var isEngaged: Bool { isHovered || dragVolume != nil }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "speaker.wave.3.fill", variableValue: displayed)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 26)
            if isExpanded {
                slider.transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .task(id: isEngaged) {
            // Expands at once; collapses a moment after the pointer leaves and no drag runs.
            if isEngaged {
                withAnimation(Self.expandAnimation) { isExpanded = true }
                return
            }
            try? await Task.sleep(for: Self.collapseDelay)
            guard !Task.isCancelled else { return }
            withAnimation(Self.expandAnimation) { isExpanded = false }
        }
        .help("Oynatıcı sesi")
        .accessibilityElement()
        .accessibilityLabel("Oynatıcı sesi")
        .accessibilityValue(displayed.formatted(.percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.1 : -0.1
            onChange(min(max(volume + step, 0), 1))
        }
    }

    private var slider: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(.primary.opacity(0.85))
                    .frame(width: max(proxy.size.width * displayed, 0))
            }
            .frame(height: Self.trackHeight)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragVolume = Self.fraction(at: $0.location.x, width: proxy.size.width) }
                    .onEnded { value in
                        onChange(Self.fraction(at: value.location.x, width: proxy.size.width))
                        dragVolume = nil
                    }
            )
        }
        .frame(width: Self.sliderWidth, height: Self.hitHeight)
    }

    private static func fraction(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1)
    }
}

/// Playback speed picker for videos.
struct PlaybackRateMenu: View {
    static let rates: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    let rate: Double
    let onSelect: (Double) -> Void

    var body: some View {
        Menu {
            ForEach(Self.rates, id: \.self) { value in
                Button {
                    onSelect(value)
                } label: {
                    if abs(value - rate) < 0.01 {
                        Label(Self.label(value), systemImage: "checkmark")
                    } else {
                        Text(Self.label(value))
                    }
                }
            }
        } label: {
            Text(Self.label(rate))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(abs(rate - 1) < 0.01 ? Color.secondary : Color.accentColor)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(.quaternary.opacity(0.7), in: .capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Oynatma hızı")
        .accessibilityLabel("Oynatma hızı")
    }

    /// "1×", "1.25×", "0.5×".
    static func label(_ rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }
}

/// "Up next" line under the artist for players that expose their queue.
struct UpNextLabel: View {
    let track: UpNextTrack

    private var detail: String {
        track.artist.isEmpty ? track.title : "\(track.title) · \(track.artist)"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .font(.system(size: 9, weight: .semibold))
            Text("Sıradaki: \(detail)")
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.tertiary)
        .help("Sıradaki: \(track.title)")
    }
}

/// Synced lyrics: the previous, current and next line around the playback position; plain lyrics scroll.
struct LyricsPanel: View {
    let state: LyricsService.State
    let position: TimeInterval

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView().controlSize(.small)
            case .loaded(.synced(let lines)):
                SyncedLyricsView(lines: lines, position: position)
            case .loaded(.plain(let lines)):
                ScrollView {
                    Text(lines.joined(separator: "\n"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
            case .loaded(.instrumental):
                message("Enstrümantal", systemImage: "pianokeys")
            case .notFound:
                message("Bu şarkı için söz bulunamadı", systemImage: "text.badge.xmark")
            case .failed:
                message("Sözler yüklenemedi", systemImage: "wifi.exclamationmark")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func message(_ text: LocalizedStringKey, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
    }
}

private struct SyncedLyricsView: View {
    let lines: [LyricLine]
    let position: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let current = LyricsParser.index(at: position, in: lines)
        VStack(alignment: .leading, spacing: 3) {
            line(current.flatMap { $0 > 0 ? lines[$0 - 1].text : nil }, isCurrent: false)
            line(current.map { lines[$0].text } ?? "♪", isCurrent: true)
            line(lines.indices.contains((current ?? -1) + 1) ? lines[(current ?? -1) + 1].text : nil, isCurrent: false)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(current.map { lines[$0].text } ?? "")
    }

    private func line(_ text: String?, isCurrent: Bool) -> some View {
        Text(text.map { $0.isEmpty ? "♪" : $0 } ?? " ")
            .font(.system(size: isCurrent ? 14 : 11, weight: isCurrent ? .semibold : .medium))
            .foregroundStyle(isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .lineLimit(1)
            .contentTransition(.opacity)
            .id(text)
    }
}
