import AppKit
import OSLog
import UserNotifications

/// Side effects fired by `TimerService` (permissions, sound, system notification).
@MainActor
protocol TimerNotifier: AnyObject {
    /// Called on every start; the first call may request notification authorization.
    func prepare()
    func timerDidFinish(_ completion: TimerCompletion)
}

/// Posts a `UNUserNotification` and plays the "Glass" system sound.
@MainActor
final class UserNotificationTimerNotifier: TimerNotifier {
    private static let soundName = "Glass"
    private static let identifierPrefix = "\(AppIdentity.bundleID).timer."

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Timer")
    private let presenter = TimerNotificationPresenter()
    private var hasRequestedAuthorization = false

    init() {}

    func prepare() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil {
            center.delegate = presenter
        }
        Task { [logger] in
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                logger.info("Notification authorization granted: \(granted)")
            } catch {
                logger.error("Notification authorization failed: \(error.localizedDescription)")
            }
        }
    }

    func timerDidFinish(_ completion: TimerCompletion) {
        playSound()
        postNotification(for: completion)
    }

    private func playSound() {
        guard let sound = NSSound(named: Self.soundName) else {
            logger.error("System sound \(Self.soundName) not found")
            return
        }
        sound.play()
    }

    private func postNotification(for completion: TimerCompletion) {
        let content = UNMutableNotificationContent()
        content.title = Self.title(for: completion.finishedPhase)
        content.body = Self.body(for: completion)
        let request = UNNotificationRequest(
            identifier: Self.identifierPrefix + UUID().uuidString,
            content: content,
            trigger: nil
        )
        Task { [logger] in
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                logger.error("Posting timer notification failed: \(error.localizedDescription)")
            }
        }
    }

    nonisolated static func title(for phase: TimerPhase) -> String {
        switch phase {
        case .countdown: "Zamanlayıcı bitti"
        case .work: "Odak oturumu tamamlandı"
        case .shortBreak, .longBreak: "Mola bitti"
        }
    }

    nonisolated static func body(for completion: TimerCompletion) -> String {
        guard let next = completion.nextPhase else { return "Zamanlayıcın bitti." }
        let verb = completion.didAutoStartNext ? "başladı" : "sırada"
        return "\(next.title) \(verb)."
    }
}

/// Lets timer banners appear even while NotchHub is the active app.
private final class TimerNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
