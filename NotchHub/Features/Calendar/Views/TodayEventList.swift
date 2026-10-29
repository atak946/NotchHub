import SwiftUI

/// Right column: the rest of today, optionally grouped by account or meeting app.
struct TodayEventList: View {
    @Bindable var calendar: CalendarService
    let excludedEventID: CalendarEvent.ID?

    var body: some View {
        let groups = calendar.groupedTodayEvents(excluding: excludedEventID)
        VStack(alignment: .leading, spacing: 6) {
            header(count: groups.reduce(0) { $0 + $1.events.count })
            if groups.isEmpty {
                Text("Bugün başka bir şey yok")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(groups) { group in
                            if calendar.grouping != .none {
                                GroupHeader(group: group)
                            }
                            ForEach(group.events) { event in
                                TodayEventRow(event: event, showsAccount: calendar.grouping != .account) {
                                    calendar.join(event)
                                } onOpen: {
                                    calendar.openCalendarApp()
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 6) {
            Text("Bugün ilerleyen saatlerde")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .background(.quaternary, in: .capsule)
            }
            Spacer(minLength: 0)
            if !calendar.sourceDiagnostics.isEmpty {
                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .help(diagnosticsText)
            }
            Picker("Grup", selection: $calendar.grouping) {
                ForEach(CalendarGrouping.allCases) { grouping in
                    Image(systemName: grouping.systemImage)
                        .help(grouping.title)
                        .tag(grouping)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
            .frame(width: CalendarMetrics.groupingPickerWidth)
            .help("Etkinlikleri grupla")
        }
    }
}

extension TodayEventList {
    /// One line per source, e.g. "macOS Calendar: 2 events today".
    private var diagnosticsText: String {
        calendar.sourceDiagnostics
            .map { "\($0.name): \($0.summary)" }
            .joined(separator: "\n")
    }
}

private struct GroupHeader: View {
    let group: CalendarEventGroup

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: group.systemImage)
            Text(group.title)
                .lineLimit(1)
            Text("\(group.events.count)")
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.top, 4)
        .padding(.leading, 2)
    }
}

private struct TodayEventRow: View {
    let event: CalendarEvent
    let showsAccount: Bool
    let onJoin: () -> Void
    let onOpen: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(event.calendarColor.color)
                .frame(width: 6, height: 6)
            Group {
                if event.isAllDay {
                    Text("Tüm gün")
                } else {
                    Text(event.start, format: .dateTime.hour().minute())
                }
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 44, alignment: .leading)

            Text(event.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if showsAccount {
                Image(systemName: event.account.kind.systemImage)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .help(event.account.displayTitle)
            }
            if let link = event.meetingLink {
                Button(action: onJoin) {
                    Image(systemName: link.provider.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isHovered ? AnyShapeStyle(link.provider.tint.color) : AnyShapeStyle(.secondary))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(CalendarPressableStyle())
                .help("\(link.provider.displayName) toplantısına katıl")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
            in: .rect(cornerRadius: CalendarMetrics.rowCornerRadius)
        )
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onOpen)
        .animation(CalendarMetrics.animation, value: isHovered)
        .help("\(event.title) — \(event.calendarTitle)")
    }
}
