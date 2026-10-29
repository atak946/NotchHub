import SwiftUI

/// The two halves of the shelf module.
enum ShelfSegment: String, CaseIterable, Identifiable, Sendable {
    case shelf
    case clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shelf: String(localized: "Raf")
        case .clipboard: String(localized: "Pano")
        }
    }

    var systemImage: String {
        switch self {
        case .shelf: "tray.full"
        case .clipboard: "list.clipboard"
        }
    }
}

/// Compact capsule switch between String(localized: "Raf") and String(localized: "Pano") with a sliding highlight.
struct ShelfSegmentPicker: View {
    private static let fontSize: CGFloat = 11

    @Binding var selection: ShelfSegment
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ShelfSegment.allCases) { segment in
                Button {
                    selection = segment
                } label: {
                    Label(segment.title, systemImage: segment.systemImage)
                        .font(.system(size: Self.fontSize, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(selection == segment ? .primary : .secondary)
                        .background {
                            if selection == segment {
                                Capsule()
                                    .fill(.quaternary)
                                    .matchedGeometryEffect(id: "segment", in: highlight)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == segment ? .isSelected : [])
            }
        }
        .padding(2)
        .background(.quaternary.opacity(0.4), in: .capsule)
        .animation(.snappy(duration: 0.2), value: selection)
    }
}
