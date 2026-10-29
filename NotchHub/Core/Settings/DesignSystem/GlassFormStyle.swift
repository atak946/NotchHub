import SwiftUI

/// Renders a settings `Form` as a stack of frosted cards: each `Section` becomes its title above
/// a glass card whose rows are separated by hairlines, and its footer below. The feature sections
/// keep using plain `Section`, `Toggle`, `Picker` and `LabeledContent`; this style and the
/// control styles it installs restyle them. The form does not scroll; the page around it does.
struct GlassFormStyle: FormStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: SettingsTheme.Spacing.l) {
            ForEach(sections: configuration.content) { section in
                GlassFormSection(section: section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .toggleStyle(GlassToggleStyle())
        .labeledContentStyle(GlassLabeledContentStyle())
        .buttonStyle(GlassButtonStyle())
        .pickerStyle(.menu)
        .textFieldStyle(.roundedBorder)
        .tint(SettingsTheme.Palette.brand)
        .controlSize(.regular)
    }
}

private struct GlassFormSection: View {
    let section: SectionConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.Spacing.s - 2) {
            if !section.header.isEmpty {
                section.header
                    .font(SettingsTheme.Typography.sectionTitle)
                    .foregroundStyle(SettingsTheme.Palette.textSecondary)
                    .padding(.leading, SettingsTheme.Spacing.xs)
                    .accessibilityAddTraits(.isHeader)
            }
            if !section.content.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(section.content) { row in
                        if row.id != section.content.first?.id {
                            GlassDivider(leadingInset: SettingsTheme.Spacing.rowHorizontal)
                        }
                        row
                            .font(SettingsTheme.Typography.row)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, SettingsTheme.Spacing.rowHorizontal)
                            .padding(.vertical, SettingsTheme.Spacing.rowVertical)
                    }
                }
                .glassSurface()
            }
            if !section.footer.isEmpty {
                section.footer
                    .font(.caption)
                    .foregroundStyle(SettingsTheme.Palette.textTertiary)
                    .padding(.horizontal, SettingsTheme.Spacing.xs)
            }
        }
    }
}
