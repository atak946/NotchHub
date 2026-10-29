import SwiftUI

/// The list of README screenshots: the state each one needs and the view that draws it.
@MainActor
enum ScreenshotPlan {
    struct Shot {
        let name: String
        let size: CGSize
        /// `ImageRenderer` draws AppKit-backed controls (toggles, pickers, menus) as placeholders, while
        /// a hosting view drops layer shadows and blurs; each shot uses whichever draws it correctly.
        var usesHostingView = false
        /// Pixels per point; the large Settings shots use less to stay within the README size budget.
        var scale: CGFloat = 2
        let prepare: @MainActor (DemoStage) -> Void
        let content: @MainActor (DemoStage) -> AnyView
    }

    static let heroSize = CGSize(width: 1200, height: 340)
    static let panelSize = CGSize(width: 960, height: 310)
    static let compactSize = CGSize(width: 860, height: 76)
    static let settingsScale: CGFloat = 1.5
    static let alertSize = CGSize(width: 860, height: 150)

    static var shots: [Shot] {
        [
            panel("hero", module: .media, size: heroSize),
            notch("collapsed", size: compactSize) { $0.startTimer() },
            panel("panel-calendar", module: .calendar, usesHostingView: true),
            panel("panel-shelf", module: .shelf, usesHostingView: true),
            panel("panel-notes", module: .notes, usesHostingView: true),
            panel("panel-timer", module: .timer),
            panel("panel-status", module: .status, usesHostingView: true),
            notch("alert-message-hidden", size: alertSize) { $0.alerts.post(messageAlert()) },
            notch("alert-message-revealed", size: alertSize) { stage in
                stage.alerts.post(messageAlert())
                stage.alerts.revealContent()
            },
            notch("alert-charging", size: alertSize) { $0.alerts.post(chargingAlert()) },
            notch("hud-volume", size: compactSize) { stage in
                stage.services.hud.center.show(HUDReading(kind: .volume, level: DemoFixtures.volumeLevel))
            },
            settings("settings-general", category: .general),
            settings("settings-notifications", category: .notifications),
            settings("settings-search", category: .notifications, query: DemoFixtures.settingsSearchQuery),
        ]
    }

    // MARK: Builders

    private static func notch(
        _ name: String,
        size: CGSize,
        usesHostingView: Bool = false,
        prepare: @escaping @MainActor (DemoStage) -> Void
    ) -> Shot {
        Shot(name: name, size: size, usesHostingView: usesHostingView, prepare: prepare) { stage in
            AnyView(DemoNotchScene(stage: stage, size: size))
        }
    }

    private static func panel(
        _ name: String,
        module: NotchModule,
        size: CGSize = panelSize,
        usesHostingView: Bool = false
    ) -> Shot {
        notch(name, size: size, usesHostingView: usesHostingView) { stage in
            stage.model.select(module)
            stage.model.isExpanded = true
        }
    }

    private static func settings(_ name: String, category: SettingsCategory, query: String = "") -> Shot {
        Shot(name: name, size: DemoSettingsScene.size, usesHostingView: true, scale: settingsScale, prepare: { _ in }) { stage in
            AnyView(DemoSettingsScene(stage: stage, category: category, query: query))
        }
    }

    // MARK: Alerts

    static func messageAlert() -> NotchAlert {
        NotchAlert(
            module: .status,
            systemImage: "message.fill",
            title: DemoFixtures.messageSender,
            subtitle: DemoFixtures.hiddenMessagePlaceholder,
            actionTitle: String(localized: "Aç"),
            action: {},
            appBundleID: DemoFixtures.messageAppBundleID,
            appName: DemoFixtures.messageAppName,
            sender: DemoFixtures.messageSender,
            concealedSubtitle: DemoFixtures.messageText
        )
    }

    static func chargingAlert() -> NotchAlert {
        let content = ChargingAlertContent(event: ChargingEvent(kind: .charging, snapshot: DemoFixtures.chargingSnapshot))
        return NotchAlert(
            module: nil,
            systemImage: content.glyph.systemImage,
            title: content.title,
            subtitle: content.subtitle,
            style: content.style,
            autoDismissAfter: content.duration,
            appName: String(localized: "Pil"),
            battery: content.glyph
        )
    }
}
