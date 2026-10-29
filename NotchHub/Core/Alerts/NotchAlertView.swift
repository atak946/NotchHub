import SwiftUI

/// Alert content laid into the black notch: source and time beside the hardware notch,
/// the icon, text and actions right below it, and the countdown along the bottom edge.
struct NotchAlertView: View {
    struct Layout: Equatable {
        /// Height of the hardware (or virtual) notch band at the top.
        let notchHeight: CGFloat
        /// Horizontal inset of the content from the alert edges.
        let sideInset: CGFloat
        /// Room for each label beside the notch; labels hide when it is too narrow.
        let wingWidth: CGFloat
        /// Extra inset of the countdown line (beyond `sideInset`) so it stays clear of the bottom corners.
        let barInset: CGFloat
    }

    static let rowTopGap: CGFloat = 2
    static let rowHeight: CGFloat = 46
    private static let barBottomInset: CGFloat = 7
    private static let minimumWingWidth: CGFloat = 36

    let alert: NotchAlert
    let center: NotchAlertCenter
    let layout: Layout
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if layout.wingWidth >= Self.minimumWingWidth {
                AlertWings(alert: alert, queuedCount: center.queue.count, wingWidth: layout.wingWidth)
                    .frame(height: layout.notchHeight)
            } else {
                Color.clear.frame(height: layout.notchHeight)
            }

            row
                .frame(height: Self.rowHeight)
                .padding(.top, Self.rowTopGap)

            Spacer(minLength: 0)

            AlertCountdownBar(countdown: center.countdown, tint: alert.style.tint)
                .padding(.horizontal, max(layout.barInset, 0))
                .padding(.bottom, Self.barBottomInset)
        }
        .padding(.horizontal, layout.sideInset)
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
        .onHover { center.isHovered = $0 }
        .help(alert.module.map { String(localized: "\($0.title) aç") } ?? "")
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Aç", onOpen)
    }

    private var row: some View {
        HStack(spacing: 12) {
            AlertLeadingIcon(alert: alert)

            VStack(alignment: .leading, spacing: 1) {
                Text(alert.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if alert.isContentConcealed {
                    AlertConcealedLine(text: alert.subtitle)
                        .transition(.opacity)
                } else if let subtitle = alert.displayedSubtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                        .contentTransition(.numericText())
                        .transition(.blurReplace)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.3), value: alert.isContentRevealed)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)

            if alert.isContentConcealed {
                Button("Göster") { center.revealContent() }
                    .buttonStyle(AlertActionButtonStyle(tint: alert.style.tint))
                    .help("Gizlenen içeriği göster")
                    .accessibilityLabel("İçeriği göster")
            }

            if let secondaryTitle = alert.secondaryActionTitle {
                Button(secondaryTitle) { center.performSecondaryAction() }
                    .buttonStyle(AlertActionButtonStyle(tint: .white))
            }

            if let actionTitle = alert.actionTitle {
                Button(actionTitle) { center.performAction() }
                    .buttonStyle(AlertActionButtonStyle(tint: alert.style.tint))
            }

            AlertCloseButton { center.dismiss() }
        }
    }

    private var accessibilityText: String {
        [alert.style.accessibilityName, alert.sender ?? alert.sourceLabel, alert.title, alert.displayedSubtitle]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// "İçerik gizlendi" with an eye.slash glyph, styled quieter than real message text.
private struct AlertConcealedLine: View {
    let text: String?

    var body: some View {
        Label {
            Text(text ?? String(localized: "İçerik gizlendi"))
        } icon: {
            Image(systemName: "eye.slash")
                .font(.system(size: 10, weight: .semibold))
        }
        .labelStyle(.titleAndIcon)
        .font(.system(size: 12).italic())
        .foregroundStyle(.white.opacity(0.42))
        .lineLimit(1)
    }
}

/// Labels on both sides of the hardware notch: source on the left, queue pill and time on the right.
private struct AlertWings: View {
    private static let dotSize: CGFloat = 5

    let alert: NotchAlert
    let queuedCount: Int
    let wingWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(alert.style.tint)
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .shadow(color: alert.style.tint.opacity(0.8), radius: 3)
                Text(alert.sourceLabel)
                    .lineLimit(1)
            }
            .frame(width: wingWidth, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if queuedCount > 0 {
                    Text("+\(queuedCount)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                        .contentTransition(.numericText(value: Double(queuedCount)))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(.white.opacity(0.14), in: .capsule)
                        .accessibilityLabel("\(queuedCount) bildirim daha")
                }
                TimelineView(.everyMinute) { context in
                    Text(alert.timestampText ?? AlertTimestampFormatter.text(postedAt: alert.postedAt, now: context.date))
                        .contentTransition(.numericText())
                }
            }
            .frame(width: wingWidth, alignment: .trailing)
            .animation(.snappy, value: queuedCount)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.5))
    }
}
