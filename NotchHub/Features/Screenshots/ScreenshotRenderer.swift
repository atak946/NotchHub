import AppKit
import OSLog
import SwiftUI

/// Renders the README screenshots from demo data, writes them as PNGs and quits. Launched with
/// `--render-screenshots <dir>`; the language comes from the process (`-AppleLanguages (en)`).
@MainActor
enum ScreenshotRenderer {
    private static let settleDelay: Duration = .milliseconds(150)
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Screenshots")

    /// Starts rendering when screenshot mode was requested; the caller then skips the normal startup.
    static func runIfRequested() -> Bool {
        guard let directory = ScreenshotMode.outputDirectory() else { return false }
        NSApp.setActivationPolicy(.prohibited)
        // Demo time is always mid-morning, so the agenda is full and the real time zone never shows.
        DemoClock.apply()
        Task { @MainActor in
            let succeeded = await render(to: directory)
            exit(succeeded ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        return true
    }

    private static func render(to directory: URL) async -> Bool {
        let stage: DemoStage
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            stage = try DemoStage(now: Date())
        } catch {
            report("Screenshot setup failed: \(error.localizedDescription)")
            return false
        }
        defer { stage.environment.cleanUp() }
        await stage.prepare()
        var failures = 0
        for shot in ScreenshotPlan.shots {
            stage.reset()
            shot.prepare(stage)
            try? await Task.sleep(for: settleDelay)
            let url = directory.appendingPathComponent("\(shot.name).png")
            if !write(shot, stage: stage, to: url) { failures += 1 }
        }
        guard ModuleCoreServices.liveCreationCount == 0 else {
            report("Live services were created during screenshot rendering")
            return false
        }
        report("Rendered \(ScreenshotPlan.shots.count - failures) of \(ScreenshotPlan.shots.count) screenshots")
        return failures == 0
    }

    private static func write(_ shot: ScreenshotPlan.Shot, stage: DemoStage, to url: URL) -> Bool {
        let view = shot.content(stage)
            .environment(\.locale, Locale.current)
            .environment(\.timeZone, DemoClock.timeZone)
            .environment(\.colorScheme, .dark)
            .defaultAppStorage(stage.environment.defaults)
        let image = shot.usesHostingView
            ? hostingSnapshot(of: view, size: shot.size, scale: shot.scale)
            : imageRendererSnapshot(of: view, size: shot.size, scale: shot.scale)
        guard let image, let data = PNGQuantizer.pngData(from: image) else {
            report("Could not render \(shot.name)")
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            report("Could not write \(shot.name): \(error.localizedDescription)")
            return false
        }
    }

    /// Progress goes to stderr too, because the render script runs the binary from a terminal.
    private static func report(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private static func imageRendererSnapshot(of view: some View, size: CGSize, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.cgImage
    }

    /// For AppKit-backed controls, which only draw through a real hosting view.
    private static func hostingSnapshot(of view: some View, size: CGSize, scale: CGFloat) -> CGImage? {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.cgImage
    }
}
