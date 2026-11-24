import AppKit
import SwiftUI

/// The hidden icons, plus the button that shows them in the menu bar for arranging.
struct MenuBarContainerView: View {
    private static let maxRowWidth: CGFloat = 230
    private static let spacing: CGFloat = 4
    private static let padding: CGFloat = 10
    private static let messageWidth: CGFloat = 220
    private static let cornerRadius: CGFloat = 16
    /// Icons keep the menu bar's black or white, so the background has to contrast like the menu bar.
    private static let backgroundOpacity = 0.72
    private static let separatorOpacity = 0.15
    private static let labelOpacity = 0.7

    let container: MenuBarContainer

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: Self.padding) {
            if container.items.isEmpty {
                message
            } else {
                icons
            }
            Rectangle()
                .fill(Color.primary.opacity(Self.separatorOpacity))
                .frame(height: 1)
            if container.needsCaptureAccess {
                Button { container.requestCaptureAccess() } label: {
                    Label("Canlı simgeler için izin ver", systemImage: "eye")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .help("Ekran Kaydı iznini açar. İzin verdikten sonra NotchHub'ı yeniden aç.")
            }
            Button { container.startArranging() } label: {
                Label("Simgeleri düzenle", systemImage: "arrow.left.and.right")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // A plain color: hierarchical styles turn unreadable on the glass over the tinted background.
            .foregroundStyle(Color.primary.opacity(Self.labelOpacity))
            .help("Simgeleri menü çubuğunda gösterir; ⌘ ile ayracın soluna sürüklediğin simgeler gizlenir.")
        }
        .padding(Self.padding)
        .fixedSize()
        .background(background, in: .rect(cornerRadius: Self.cornerRadius))
        .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
    }

    private var background: Color {
        (colorScheme == .dark ? Color.black : .white).opacity(Self.backgroundOpacity)
    }

    private var icons: some View {
        MenuBarFlowLayout(maxWidth: Self.maxRowWidth, spacing: Self.spacing) {
            ForEach(container.items) { item in
                MenuBarItemButton(item: item, icon: container.icons[item.id]) {
                    container.open(item)
                } secondaryAction: {
                    container.open(item, button: .right)
                }
            }
        }
    }

    private var message: some View {
        Group {
            if container.isScanning {
                ProgressView().controlSize(.small)
            } else {
                Text("Gizli simge yok. Düzenle'ye basıp simgeleri ⌘ ile ayracın soluna sürükle.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: Self.messageWidth)
        .padding(.vertical, Self.spacing)
    }
}

private struct MenuBarItemButton: View {
    private static let minWidth: CGFloat = 44
    private static let height: CGFloat = 40
    private static let horizontalPadding: CGFloat = 10
    private static let appIconSize: CGFloat = 26
    private static let appIconSizeWithValue: CGFloat = 20

    let item: MenuBarItem
    let icon: MenuBarIconCapture.Icon?
    let action: () -> Void
    let secondaryAction: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, Self.horizontalPadding)
                .frame(minWidth: Self.minWidth, minHeight: Self.height, maxHeight: Self.height)
                .background {
                    if isHovered {
                        RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay { SecondaryClickCatcher(action: secondaryAction) }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(item.name)
        .accessibilityLabel(item.name)
        .accessibilityAction(named: "Sağ tıkla", secondaryAction)
    }

    @ViewBuilder
    private var content: some View {
        if let icon {
            Image(decorative: icon.image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: icon.size.width, height: icon.size.height)
        } else {
            VStack(spacing: 1) {
                appIcon.frame(width: appIconSize, height: appIconSize)
                if let value = item.value {
                    Text(value)
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .lineLimit(1)
                }
            }
        }
    }

    private var appIconSize: CGFloat { item.value == nil ? Self.appIconSize : Self.appIconSizeWithValue }

    @ViewBuilder
    private var appIcon: some View {
        if let symbol = item.systemSymbol {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium))
        } else if let image = NSRunningApplication(processIdentifier: item.pid)?.icon {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "app.dashed").font(.system(size: 18))
        }
    }
}
