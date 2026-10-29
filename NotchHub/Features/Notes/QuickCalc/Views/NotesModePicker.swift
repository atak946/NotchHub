import SwiftUI

/// The two faces of the Notes module.
enum NotesMode: String, CaseIterable, Identifiable, Sendable {
    case notes
    case calculator

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .notes: "Notlar"
        case .calculator: "Hesap"
        }
    }
}

/// Compact "Notlar | Hesap" capsule switch, styled like the shelf's segment picker.
struct NotesModePicker: View {
    @Binding var selection: NotesMode
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NotesMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.title)
                        .font(.system(size: NotesStyle.buttonFontSize, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(selection == mode ? .primary : .secondary)
                        .background {
                            if selection == mode {
                                Capsule()
                                    .fill(.quaternary)
                                    .matchedGeometryEffect(id: "mode", in: highlight)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
        .padding(2)
        .background(.quaternary.opacity(0.4), in: .capsule)
        .animation(.snappy(duration: 0.2), value: selection)
    }
}

extension QuickCalcService {
    /// Binding for `NotesModePicker`.
    var modeBinding: Binding<NotesMode> {
        Binding(
            get: { self.isActive ? .calculator : .notes },
            set: { self.setActive($0 == .calculator) }
        )
    }
}
