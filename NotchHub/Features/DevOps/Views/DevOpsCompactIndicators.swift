import SwiftUI

/// ≤ 14 × 14 pt glyph beside the closed notch: red container badge or red endpoint glyph. EmptyView otherwise.
struct DevOpsCompactIndicators: View {
    let monitors: DevOpsMonitors

    private static let size: CGFloat = 14
    private static let dotSize: CGFloat = 5

    init(monitors: DevOpsMonitors) {
        self.monitors = monitors
    }

    var body: some View {
        if monitors.docker.hasCompactIndicator {
            glyph("shippingbox.fill", help: dockerHelp)
        } else if monitors.endpoints.hasCompactIndicator {
            glyph("network.slash", help: endpointHelp)
        } else {
            EmptyView()
        }
    }

    private func glyph(_ systemImage: String, help: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: Self.size, height: Self.size)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(.red)
                    .frame(width: Self.dotSize, height: Self.dotSize)
            }
            .help(help)
            .accessibilityElement()
            .accessibilityLabel(help)
    }

    private var dockerHelp: String {
        let unhealthy = monitors.docker.counts.unhealthy
        if unhealthy > 0 { return String(localized: "\(unhealthy) container sağlıksız") }
        guard let name = monitors.docker.lastFailure?.containerName else {
            return String(localized: "Bir container yakın zamanda başarısız oldu")
        }
        return String(localized: "\(name) yakın zamanda başarısız oldu")
    }

    private var endpointHelp: String {
        let names = monitors.endpoints.downEndpoints.map(\.displayName).joined(separator: ", ")
        return String(localized: "Kapalı: \(names)")
    }
}
