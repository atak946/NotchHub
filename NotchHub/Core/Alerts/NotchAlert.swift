import Foundation

/// A transient, animated banner that grows out of the notch ("live activity" style).
struct NotchAlert: Identifiable {
    enum Style: Sendable {
        case info
        case reminder
        case success
        case urgent

        /// Urgent and reminder alerts keep pulsing until the user reacts.
        var pulses: Bool {
            self == .urgent || self == .reminder
        }
    }

    static let defaultDuration: Duration = .seconds(6)
    /// For alerts that need attention (failures, reminders): long, but never stuck on screen.
    static let importantDuration: Duration = .seconds(30)
    /// Meeting reminders stay up long enough to join from the notch.
    static let meetingReminderDuration: Duration = .seconds(90)

    let id = UUID()
    let postedAt = Date()
    let module: NotchModule?
    /// Fallback glyph when no app icon or sender avatar can be shown.
    let systemImage: String
    let title: String
    let subtitle: String?
    let style: Style
    /// Alerts sharing a key replace each other instead of queueing (e.g. track changes).
    let coalescingKey: String?
    /// `nil` keeps the alert until it is dismissed or acted on.
    let autoDismissAfter: Duration?
    let actionTitle: String?
    let action: (@MainActor () -> Void)?
    /// Optional second button (e.g. "Yoksay"), shown before the primary action.
    let secondaryActionTitle: String?
    let secondaryAction: (@MainActor () -> Void)?
    /// Source app; its real icon replaces `systemImage` when it can be resolved (e.g. `net.whatsapp.WhatsApp`).
    let appBundleID: String?
    /// Source app display name; shown as the source label and used to find the app when there is no bundle id.
    let appName: String?
    /// A person (message sender); shows a monogram avatar with the app icon as a badge.
    let sender: String?
    /// Overrides the trailing relative time label ("şimdi", "3 dk").
    let timestampText: String?
    /// Power alerts: an animated battery ring replaces the leading icon.
    let battery: AlertBatteryGlyph?
    /// Private text (e.g. a message body) kept only in memory until the user reveals it; `subtitle`
    /// carries the placeholder meanwhile. Private so no view can render it by accident.
    private let concealedSubtitle: String?
    /// Set by `revealingContent()` when the user pressed "Göster".
    private(set) var isContentRevealed = false

    init(
        module: NotchModule?,
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        style: Style = .info,
        coalescingKey: String? = nil,
        autoDismissAfter: Duration? = NotchAlert.defaultDuration,
        actionTitle: String? = nil,
        action: (@MainActor () -> Void)? = nil,
        appBundleID: String? = nil,
        appName: String? = nil,
        sender: String? = nil,
        timestampText: String? = nil,
        battery: AlertBatteryGlyph? = nil,
        concealedSubtitle: String? = nil,
        secondaryActionTitle: String? = nil,
        secondaryAction: (@MainActor () -> Void)? = nil
    ) {
        self.module = module
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.coalescingKey = coalescingKey
        self.autoDismissAfter = autoDismissAfter
        self.actionTitle = actionTitle
        self.action = action
        self.appBundleID = appBundleID.flatMap(Self.cleaned)
        self.appName = appName.flatMap(Self.cleaned)
        self.sender = sender.flatMap(Self.cleaned)
        self.timestampText = timestampText.flatMap(Self.cleaned)
        self.battery = battery
        self.concealedSubtitle = concealedSubtitle.flatMap(Self.cleaned)
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
    }

    /// The alert hides private text that the user can reveal.
    var isContentConcealed: Bool {
        concealedSubtitle != nil && !isContentRevealed
    }

    /// The only subtitle views may render: the placeholder while concealed, the real text once revealed.
    var displayedSubtitle: String? {
        guard isContentRevealed, let concealedSubtitle else { return subtitle }
        return concealedSubtitle
    }

    /// The same alert (same id) with its concealed text revealed; unchanged when nothing is concealed.
    func revealingContent() -> NotchAlert {
        guard isContentConcealed else { return self }
        var copy = self
        copy.isContentRevealed = true
        return copy
    }

    /// Small label in the left notch wing: the app, the module, or the product name.
    var sourceLabel: String {
        appName ?? module?.title ?? "NotchHub"
    }

    private static func cleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
