import AppKit
import SwiftUI

/// macOS-style privacy dot (green camera / orange microphone) with a short pulse when it appears.
/// The pulse is skipped entirely when Reduce Motion is on.
struct PrivacyIndicatorDot: View {
    private static let dotSize: CGFloat = 7
    private static let frameSize: CGFloat = SystemIndicatorDot.frameSize
    private static let haloScale: CGFloat = 2
    private static let haloLineWidth: CGFloat = 1.5
    private static let haloOpacity: Double = 0.8
    private static let pulseDuration: TimeInterval = 1.2
    private static let pulseCount = 3

    let kind: PrivacyIndicatorKind
    let help: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .stroke(color, lineWidth: Self.haloLineWidth)
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .scaleEffect(isPulsing ? Self.haloScale : 1)
                    .opacity(isPulsing ? 0 : Self.haloOpacity)
            }
            Circle()
                .fill(color)
                .frame(width: Self.dotSize, height: Self.dotSize)
        }
        .frame(width: Self.frameSize, height: Self.frameSize)
        .help(help)
        .accessibilityElement()
        .accessibilityLabel(help)
        .onAppear(perform: pulse)
    }

    private var color: Color {
        switch kind {
        case .camera: Color(nsColor: .systemGreen)
        case .microphone: Color(nsColor: .systemOrange)
        }
    }

    private func pulse() {
        guard !reduceMotion else { return }
        let animation = Animation.easeOut(duration: Self.pulseDuration)
            .repeatCount(Self.pulseCount, autoreverses: false)
        withAnimation(animation) { isPulsing = true }
    }
}
