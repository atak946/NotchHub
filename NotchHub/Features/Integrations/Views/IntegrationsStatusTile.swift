import SwiftUI

/// ~140 × 70 pt Status tile: last external alert and today's count.
struct IntegrationsStatusTile: View {
    static let size = CGSize(width: 140, height: 70)
    private static let cornerRadius: CGFloat = 14
    private static let padding: CGFloat = 10
    private static let iconSize: CGFloat = 13
    private static let restingFill = 0.08
    private static let hoverFill = 0.14
    private static let pressedScale: CGFloat = 0.97

    private let service: ExternalAlertService
    private let action: (() -> Void)?

    @State private var isHovered = false

    /// `action` runs on click (e.g. open Settings); `nil` makes the tile static.
    init(service: ExternalAlertService, action: (() -> Void)? = nil) {
        self.service = service
        self.action = action
    }

    var body: some View {
        tile
            .onHover { isHovered = $0 }
        .help(helpText)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var tile: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(IntegrationsTileButtonStyle(pressedScale: Self.pressedScale))
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: Self.iconSize, weight: .semibold))
                    .foregroundStyle(tint)
                Text("Uyarı API")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(service.countToday)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(tint)
            }
            Text(service.lastAlert?.title ?? stateText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            lastReceivedText
        }
        .padding(Self.padding)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(
            Color.primary.opacity(isHovered ? Self.hoverFill : Self.restingFill),
            in: .rect(cornerRadius: Self.cornerRadius)
        )
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    @ViewBuilder
    private var lastReceivedText: some View {
        if let last = service.lastAlert {
            Text(last.receivedAt, style: .relative)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text("Bugün \(service.countToday)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var iconName: String {
        switch service.socketState {
        case .failed: "exclamationmark.triangle.fill"
        case .listening: "dot.radiowaves.left.and.right"
        case .starting, .stopped: service.isEnabled ? "antenna.radiowaves.left.and.right" : "bell.slash"
        }
    }

    private var stateText: String {
        guard service.isEnabled else { return "Kapalı" }
        switch service.socketState {
        case .listening: return "Uyarı bekleniyor"
        case .starting: return "Başlatılıyor…"
        case .stopped: return "Yalnızca URL şeması"
        case .failed: return "Soket başarısız"
        }
    }

    private var tint: Color {
        guard service.isEnabled else { return .secondary }
        if case .failed = service.socketState { return .red }
        return service.lastAlert?.style.alertStyle.tint ?? .blue
    }

    private var helpText: String {
        "Bugün \(service.countToday) harici uyarı · soket: \(stateText)"
    }
}

private struct IntegrationsTileButtonStyle: ButtonStyle {
    let pressedScale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
