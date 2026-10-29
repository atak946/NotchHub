import SwiftUI

/// Round initials avatar on a gradient derived from the sender's name.
struct MonogramAvatar: View {
    let name: String
    let initials: String
    let size: CGFloat

    private static let fontScale: CGFloat = 0.4

    var body: some View {
        let gradient = Monogram.gradient(for: name)
        Circle()
            .fill(LinearGradient(
                colors: [Color(gradient.top), Color(gradient.bottom)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .overlay {
                Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.75)
            }
            .overlay {
                Text(initials)
                    .font(.system(size: size * Self.fontScale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            }
            .frame(width: size, height: size)
    }
}

private extension Color {
    init(_ rgb: MonogramGradient.RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
