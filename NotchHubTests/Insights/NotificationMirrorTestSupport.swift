import Foundation
import Synchronization
@testable import NotchHub

final class InsightsFakeBannerReader: NotificationBannerReading {
    private struct State {
        var snapshot: NotificationCenterSnapshot?
        var reads = 0
        var dismissed: [String] = []
    }

    private let storage = Mutex(State(snapshot: .empty))

    var snapshot: NotificationCenterSnapshot? {
        get { storage.withLock { $0.snapshot } }
        set { storage.withLock { $0.snapshot = newValue } }
    }

    func show(_ banners: [NotificationBanner]) {
        snapshot = NotificationCenterSnapshot(banners: banners, hasBannerWindow: !banners.isEmpty)
    }

    var readCount: Int { storage.withLock { $0.reads } }
    var dismissedIDs: [String] { storage.withLock { $0.dismissed } }

    func readSnapshot() -> NotificationCenterSnapshot? {
        storage.withLock {
            $0.reads += 1
            return $0.snapshot
        }
    }

    func dismiss(bannerID: String) -> Bool {
        storage.withLock {
            $0.dismissed.append(bannerID)
            return true
        }
    }
}

@MainActor
final class InsightsFakeBannerObserver: NotificationCenterEventObserving {
    private(set) var attachCount = 0
    private(set) var detachCount = 0
    private var onEvent: (@MainActor () -> Void)?

    func attach(onEvent: @escaping @MainActor () -> Void) {
        attachCount += 1
        self.onEvent = onEvent
    }

    func detach() {
        detachCount += 1
        onEvent = nil
    }

    func fire() {
        onEvent?()
    }
}

enum InsightsBanners {
    static func make(
        _ id: String, app: String = "WhatsApp", title: String = "Ahmet Yılmaz",
        subtitle: String? = nil, body: String? = "Toplantı linkini atar mısın?"
    ) -> NotificationBanner {
        NotificationBanner(id: id, app: app, title: title, subtitle: subtitle, body: body)
    }
}
