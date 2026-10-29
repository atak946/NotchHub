import SwiftUI

/// Both Insights tiles for the Status grid (each item is a separate 140 × 70 pt grid cell).
struct InsightsStatusTiles: View {
    let insights: Insights

    init(insights: Insights) {
        self.insights = insights
    }

    var body: some View {
        if insights.unread.isEnabled {
            UnreadStatusTile(insights: insights)
        }
        if insights.timeTracker.isEnabled {
            TimeTrackerStatusTile(insights: insights)
        }
    }
}

/// Total unread plus the busiest watched apps; click opens the app with most unread.
struct UnreadStatusTile: View {
    let insights: Insights

    private static let maxListedApps = 2

    var body: some View {
        let monitor = insights.unread
        let trusted = insights.isAccessibilityTrusted
        let tint: Color = !trusted ? .orange : (monitor.totalUnread > 0 ? .blue : .gray)
        InsightsTileChrome(tint: tint, help: help(trusted: trusted), action: action(trusted: trusted)) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: trusted ? "bubble.left.and.bubble.right.fill" : "lock.fill")
                        .foregroundStyle(tint)
                    Text(trusted ? "\(monitor.totalUnread) okunmamış" : "Okunmamış")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                if trusted {
                    if let last = insights.mirror.lastMirrored {
                        Text("Son: \(last.title) · \(last.appName)")
                            .lineLimit(1)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(topApps(monitor, limit: appRowLimit)) { item in
                        HStack {
                            Text(UnreadBadgeMonitor.displayName(for: item.app)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(item.count)").monospacedDigit()
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Erişilebilirlik izni ver")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .accessibilityLabel(trusted ? "\(monitor.totalUnread) okunmamış mesaj" : "Okunmamış rozetleri için Erişilebilirlik izni gerekir")
    }

    /// One app row gives way to the "Son bildirim" line so the tile keeps its height.
    private var appRowLimit: Int {
        insights.mirror.lastMirrored == nil ? Self.maxListedApps : Self.maxListedApps - 1
    }

    private func topApps(_ monitor: UnreadBadgeMonitor, limit: Int = maxListedApps) -> [UnreadAppCount] {
        Array(monitor.counts.filter { $0.count > 0 }.sorted { $0.count > $1.count }.prefix(limit))
    }

    private func help(trusted: Bool) -> String {
        guard trusted else { return "Okunmamış rozetleri için Erişilebilirlik izni gerekir. İzin vermek için tıklayın." }
        let lines = insights.unread.counts.map { "\(UnreadBadgeMonitor.displayName(for: $0.app)): \($0.count)" }
        let last = insights.mirror.lastMirrored.map { ["Son bildirim: \($0.title) · \($0.appName)"] } ?? []
        let all = lines + last
        return all.isEmpty ? "İzlenen uygulama yok" : all.joined(separator: "\n")
    }

    private func action(trusted: Bool) -> (() -> Void)? {
        guard trusted else { return { insights.requestAccessibilityAccess() } }
        guard let busiest = topApps(insights.unread).first else { return nil }
        return { insights.unread.open(app: busiest.app) }
    }
}

/// Today's tracked total with per-client bars; click copies today's summary.
struct TimeTrackerStatusTile: View {
    let insights: Insights

    private static let maxBars = 2
    private static let barHeight: CGFloat = 3

    var body: some View {
        let tracker = insights.timeTracker
        let totals = tracker.todayClientTotals
        let total = tracker.todayTotalSeconds
        let tint: Color = tracker.isIdle ? .gray : (tracker.currentClient == nil ? .teal : .green)
        InsightsTileChrome(tint: tint, help: help(tracker), action: { tracker.copySummary() }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: tracker.isIdle ? "moon.zzz.fill" : "clock.fill")
                        .foregroundStyle(tint)
                    Text(InsightsDurationFormatter.short(seconds: total))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    if !insights.isAccessibilityTrusted {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
                if totals.isEmpty {
                    Text(tracker.rules.isEmpty ? "Ayarlar'dan kural ekleyin" : "Henüz takip edilen yok")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(totals.prefix(Self.maxBars)) { item in
                        clientBar(item, total: total, tint: tint)
                    }
                }
            }
        }
        .accessibilityLabel("\(InsightsDurationFormatter.short(seconds: total)) bugün takip edildi")
    }

    private func clientBar(_ item: ClientTotal, total: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(item.client).lineLimit(1)
                Spacer(minLength: 4)
                Text(InsightsDurationFormatter.short(seconds: item.seconds)).monospacedDigit()
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            GeometryReader { proxy in
                Capsule()
                    .fill(tint.opacity(0.85))
                    .frame(width: proxy.size.width * fraction(item.seconds, of: total))
            }
            .frame(height: Self.barHeight)
        }
    }

    private func fraction(_ part: Int, of total: Int) -> CGFloat {
        total > 0 ? CGFloat(part) / CGFloat(total) : 0
    }

    private func help(_ tracker: TimeTracker) -> String {
        let line = TimeSummaryFormatter.line(totalSeconds: tracker.todayTotalSeconds, totals: tracker.todayClientTotals)
        let window = tracker.isAccessibilityTrusted ? "" : "\nPencere başlığı kuralları için Erişilebilirlik izni gerekir."
        return "\(line)\nÖzeti kopyalamak için tıklayın.\(window)"
    }
}
