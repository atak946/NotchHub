import SwiftUI

/// Glass sidebar: search field, grouped category rows and a glowing selection pill. While searching
/// it lists only matching categories, each with up to three matched setting names. Arrow keys move
/// the selection from the search field or the list; Return opens the first match; Escape clears.
struct SettingsSidebar: View {
    private static let isEnglish = Bundle.main.preferredLocalizations.first?.hasPrefix("en") ?? false

    @Binding var selection: SettingsCategory
    @Binding var query: String

    @FocusState private var isSearchFocused: Bool
    @Namespace private var pillNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSearching: Bool {
        !SettingsSearchNormalizer.tokens(of: query).isEmpty
    }

    var body: some View {
        let results = SettingsSearchIndex.search(query)
        VStack(alignment: .leading, spacing: SettingsTheme.Spacing.m) {
            SettingsSearchField(text: $query, isFocused: $isSearchFocused) { key in
                handle(key, visible: results.map(\.category))
            }
            if isSearching, results.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(results)
            }
        }
        .padding(.top, SettingsTheme.Spacing.titleBar + SettingsTheme.Spacing.m)
        .padding(.horizontal, SettingsTheme.Spacing.s + 2)
        .padding(.bottom, SettingsTheme.Spacing.s + 2)
        .background {
            Rectangle()
                .fill(Color.black.opacity(0.22))
                .overlay(alignment: .trailing) {
                    Rectangle().fill(SettingsTheme.Palette.hairline).frame(width: 1)
                }
                .ignoresSafeArea()
        }
    }

    private func list(_ results: [SettingsSearchResult]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsTheme.Spacing.xxs) {
                ForEach(SettingsCategoryGroup.allCases) { group in
                    let rows = results.filter { $0.category.group == group }
                    if !rows.isEmpty {
                        Text(group.title)
                            .font(SettingsTheme.Typography.sidebarGroup)
                            .tracking(0.6)
                            .foregroundStyle(SettingsTheme.Palette.textTertiary)
                            .padding(.leading, SettingsTheme.Spacing.s)
                            .padding(.top, group == results.first?.category.group ? 0 : SettingsTheme.Spacing.m)
                            .padding(.bottom, SettingsTheme.Spacing.xxs)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(rows) { result in
                            row(result)
                        }
                    }
                }
            }
            .padding(.bottom, SettingsTheme.Spacing.s)
        }
        .scrollIndicators(.never)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            handle(press.key, visible: results.map(\.category))
        }
    }

    private func row(_ result: SettingsSearchResult) -> some View {
        SettingsSidebarRow(
            category: result.category,
            matchedItems: result.matchedItems.map { $0.displayText(isEnglish: Self.isEnglish) },
            isSelected: result.category == selection,
            pillNamespace: pillNamespace,
            animatesPill: !reduceMotion
        ) {
            select(result.category)
        }
    }

    private func select(_ category: SettingsCategory) {
        withAnimation(reduceMotion ? nil : SettingsTheme.Motion.selection) {
            selection = category
        }
    }

    /// Arrow keys move through the visible rows; Return opens the first one; Escape clears the query.
    private func handle(_ key: KeyEquivalent, visible: [SettingsCategory]) -> KeyPress.Result {
        switch key {
        case .escape:
            guard !query.isEmpty else { return .ignored }
            query = ""
            return .handled
        case .return:
            guard let first = visible.first else { return .ignored }
            select(first)
            return .handled
        case .upArrow, .downArrow:
            guard !visible.isEmpty else { return .ignored }
            let step = key == .upArrow ? -1 : 1
            let current = visible.firstIndex(of: selection) ?? (step > 0 ? -1 : visible.count)
            let next = min(max(current + step, 0), visible.count - 1)
            select(visible[next])
            return .handled
        default:
            return .ignored
        }
    }
}

private struct SettingsSidebarRow: View {
    private static let pillID = "settings.selectionPill"
    private static let iconSize: CGFloat = 22

    let category: SettingsCategory
    let matchedItems: [String]
    let isSelected: Bool
    let pillNamespace: Namespace.ID
    let animatesPill: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsTheme.Spacing.s + 2) {
                GlassIconTile(symbol: category.systemImage, tint: category.tint, size: Self.iconSize, glows: isSelected)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(SettingsTheme.Palette.textPrimary)
                        .lineLimit(1)
                    if !matchedItems.isEmpty {
                        Text(matchedItems.joined(separator: " · "))
                            .font(.system(size: 10.5))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.8) : SettingsTheme.Palette.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SettingsTheme.Spacing.s)
            .padding(.vertical, 5)
            .background { background }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(SettingsTheme.Motion.hover, value: isHovered)
        .accessibilityLabel(Text(category.title))
        .accessibilityValue(Text(matchedItems.joined(separator: ", ")))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: SettingsTheme.Radius.m, style: .continuous)
        if isSelected {
            let pill = shape
                .fill(SettingsTheme.brandGradient.opacity(0.85))
                .overlay(shape.strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                .glassGlow(SettingsTheme.Palette.brand, radius: 6, opacity: 0.6)
            if animatesPill {
                pill.matchedGeometryEffect(id: Self.pillID, in: pillNamespace)
            } else {
                pill
            }
        } else if isHovered {
            shape.fill(SettingsTheme.Palette.hoverFill)
        }
    }
}

/// Glass search field at the top of the sidebar.
private struct SettingsSearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onKey: (KeyEquivalent) -> KeyPress.Result

    var body: some View {
        HStack(spacing: SettingsTheme.Spacing.s - 2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(SettingsTheme.Palette.textTertiary)
                .accessibilityHidden(true)
            TextField("Ayarlarda ara", text: $text, prompt: Text("Ayarlarda ara"))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused(isFocused)
                .labelsHidden()
                .onKeyPress(keys: [.upArrow, .downArrow, .return, .escape]) { press in
                    onKey(press.key)
                }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SettingsTheme.Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Aramayı temizle"))
            }
        }
        .padding(.horizontal, SettingsTheme.Spacing.s + 2)
        .padding(.vertical, 6)
        .background {
            let shape = RoundedRectangle(cornerRadius: SettingsTheme.Radius.m, style: .continuous)
            shape.fill(Color.white.opacity(0.07))
                .overlay(shape.strokeBorder(Color.white.opacity(isFocused.wrappedValue ? 0.28 : 0.1), lineWidth: 1))
        }
    }
}
