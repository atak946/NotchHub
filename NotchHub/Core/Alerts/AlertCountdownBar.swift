import SwiftUI

/// Thin line along the bottom inner edge that drains until the alert auto-dismisses.
/// Driven by one linear animation per run, so nothing ticks while it is idle or paused.
struct AlertCountdownBar: View {
    static let height: CGFloat = 2

    let countdown: AlertCountdown?
    let tint: Color
    @State private var fraction: Double = 1

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.08))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.55), tint], startPoint: .leading, endPoint: .trailing))
                    .scaleEffect(x: fraction, anchor: .leading)
            }
            .frame(height: Self.height)
            .opacity(countdown == nil ? 0 : 1)
            .onAppear(perform: sync)
            .onChange(of: countdown) { sync() }
            .accessibilityHidden(true)
    }

    private func sync() {
        guard let countdown else { return }
        let now = ContinuousClock.now
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) { fraction = countdown.fraction(at: now) }
        guard countdown.isRunning else { return }
        let seconds = countdown.remaining(at: now) / .seconds(1)
        withAnimation(.linear(duration: seconds)) { fraction = 0 }
    }
}
