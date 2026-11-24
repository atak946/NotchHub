import ApplicationServices
import SwiftUI

/// Made-up menu bar icons for the screenshot of the menu bar box; no real app's icon or name.
@MainActor
enum DemoMenuBarIcons {
    private static let scale: CGFloat = 2

    private static let views: [(name: String, view: AnyView)] = [
        ("Shield", AnyView(Image(systemName: "checkmark.shield.fill"))),
        ("VPN", AnyView(vpn)),
        ("System", AnyView(system)),
        ("Battery", AnyView(battery)),
        ("Cloud", AnyView(Image(systemName: "cloud.fill"))),
        ("Tasks", AnyView(tasks)),
    ]

    private static var vpn: some View {
        Image(systemName: "lock.fill")
            .padding(.trailing, 5)
            .overlay(alignment: .bottomTrailing) {
                Circle().fill(.green).frame(width: 7, height: 7)
            }
    }

    private static var system: some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform.path.ecg.rectangle")
            gauge("CPU", "11%")
            gauge("RAM", "56%")
        }
    }

    private static var battery: some View {
        HStack(spacing: 4) {
            Text("80%").font(.system(size: 12, weight: .medium).monospacedDigit())
            Image(systemName: "battery.75percent")
        }
    }

    private static var tasks: some View {
        HStack(spacing: 4) {
            Image(systemName: "checklist")
            Text("3").font(.system(size: 12, weight: .medium))
        }
    }

    private static func gauge(_ title: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(title)
            Text(value).monospacedDigit()
        }
        .font(.system(size: 8, weight: .semibold))
    }

    /// Items for the container; the accessibility element is a stand-in that is never messaged.
    static func items() -> [MenuBarItem] {
        views.enumerated().map { index, entry in
            MenuBarItem(
                id: entry.name, pid: 0, bundleID: nil, name: entry.name, value: nil, identifier: nil,
                frame: CGRect(x: index, y: 0, width: 1, height: 1), element: AXUIElementCreateSystemWide()
            )
        }
    }

    static func icons() -> [String: MenuBarIconCapture.Icon] {
        views.reduce(into: [:]) { icons, entry in
            let renderer = ImageRenderer(content: entry.view.font(.system(size: 15, weight: .semibold)).foregroundStyle(.white))
            renderer.scale = scale
            guard let image = renderer.cgImage else { return }
            let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
            icons[entry.name] = MenuBarIconCapture.Icon(image: image, size: size)
        }
    }
}

/// The real box view hanging from a chevron in the demo menu bar.
struct DemoMenuBarBoxScene: View {
    private static let rightMargin: CGFloat = 60
    private static let gap: CGFloat = 8

    let stage: DemoStage
    let size: CGSize

    var body: some View {
        DemoDesktop(size: size, showsChevron: true) {
            MenuBarContainerView(container: stage.services.menuBar)
                .padding(.top, DemoStage.geometry.notchSize.height + Self.gap)
                .padding(.trailing, Self.rightMargin)
                .frame(width: size.width, height: size.height, alignment: .topTrailing)
        }
    }
}
