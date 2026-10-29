import Foundation

/// The gentle reminder shown in the notch when a scheduled check finds an update in the background.
enum UpdateReminderAlert {
    static let coalescingKey = "updates.available"
    static let systemImage = "arrow.down.circle.fill"
    static let appName = "NotchHub"
    /// Long enough to notice; Sparkle reminds again on the next scheduled check.
    static let duration: Duration = .seconds(15)

    static func make(version: String, onUpdate: @escaping @MainActor () -> Void) -> NotchAlert {
        NotchAlert(
            module: nil,
            systemImage: systemImage,
            title: "NotchHub \(version) hazır",
            subtitle: "Güncellemek için tıkla",
            style: .info,
            coalescingKey: coalescingKey,
            autoDismissAfter: duration,
            actionTitle: "Güncelle",
            action: onUpdate,
            appName: appName
        )
    }
}
