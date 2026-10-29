import SwiftUI

/// A miniature menu bar whose notch breathes open into a panel and closes again.
struct OnboardingNotchPreview: View {
    private static let closedSize = CGSize(width: 118, height: 22)
    private static let openSize = CGSize(width: 300, height: 108)
    private static let barHeight: CGFloat = 22
    private static let cycle: Double = 2.6
    private static let previewIcons = ["tray.full", "music.note", "timer", "calendar", "note.text"]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOpen = false

    var body: some View {
        let size = isOpen ? Self.openSize : Self.closedSize
        ZStack(alignment: .top) {
            menuBar
            ZStack(alignment: .top) {
                NotchShape(topRadius: 6, bottomRadius: isOpen ? 22 : 9)
                    .fill(OnboardingStyle.accent.opacity(isOpen ? 0.5 : 0.2))
                    .blur(radius: 14)
                    .offset(y: 6)
                NotchShape(topRadius: 6, bottomRadius: isOpen ? 22 : 9)
                    .fill(.black)
                NotchShape(topRadius: 6, bottomRadius: isOpen ? 22 : 9)
                    .stroke(.white.opacity(0.08), lineWidth: 0.5)
                panelContent
                    .opacity(isOpen ? 1 : 0)
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: 380, height: Self.openSize.height + 12, alignment: .top)
        .task { await animateLoop() }
        .accessibilityElement()
        .accessibilityLabel("Çentik önizlemesi")
    }

    private var menuBar: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.white.opacity(0.06))
            .frame(height: Self.barHeight)
            .overlay(alignment: .trailing) {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(.white.opacity(0.25)).frame(width: 14, height: 5)
                    }
                }
                .padding(.trailing, 12)
            }
    }

    private var panelContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ForEach(Self.previewIcons, id: \.self) { icon in
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(icon == "music.note" ? OnboardingStyle.accent : .white.opacity(0.55))
                }
            }
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(
                        colors: [OnboardingStyle.accent, OnboardingStyle.accentSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(.white.opacity(0.8)).frame(width: 110, height: 6)
                    Capsule().fill(.white.opacity(0.35)).frame(width: 70, height: 5)
                    Capsule().fill(.white.opacity(0.15)).frame(width: 160, height: 3)
                }
            }
        }
        .padding(.top, 30)
    }

    private func animateLoop() async {
        guard !reduceMotion else {
            isOpen = true
            return
        }
        while !Task.isCancelled {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { isOpen.toggle() }
            do {
                try await Task.sleep(for: .seconds(Self.cycle))
            } catch {
                return
            }
        }
    }
}
