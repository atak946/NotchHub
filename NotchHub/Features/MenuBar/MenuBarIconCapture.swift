import AppKit
import CoreGraphics

/// Pictures of the icons as the menu bar draws them, hidden ones included. Needs Screen Recording access.
struct MenuBarIconCapture: Sendable {
    /// ScreenCaptureKit refuses windows that are off screen; this older call does not, but the SDK no
    /// longer declares it, so it is looked up at run time and simply missing if macOS drops it.
    private typealias CreateImage = @convention(c) (CGRect, CFArray, UInt32) -> Unmanaged<CGImage>?
    private static let createImage: CreateImage? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImageFromArray") else { return nil }
        return unsafeBitCast(symbol, to: CreateImage.self)
    }()
    private static let boundsIgnoreFraming: UInt32 = 1
    private static let minOpaqueAlpha: UInt8 = 50
    private static let bytesPerPixel = 4

    struct Icon: @unchecked Sendable {
        let image: CGImage
        /// Size in the menu bar, in points.
        let size: CGSize
    }

    static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")

    /// Asks macOS for access. Its dialog only shows the first time, so the settings page opens as well.
    @MainActor
    static func requestAccess() {
        guard !CGRequestScreenCaptureAccess(), let settingsURL else { return }
        NSWorkspace.shared.open(settingsURL)
    }

    func icons(for items: [MenuBarItem]) async -> [String: Icon] {
        guard Self.isAllowed else { return [:] }
        let windows = MenuBarHostWindow.all()
        return items.reduce(into: [:]) { icons, item in
            // The copy on the display in use comes first; the built-in display's may be empty or dimmed.
            let candidates = windows.filter { $0.hosts(item.frame) }
                + windows.filter { $0.name != nil && $0.name == item.bundleID }
            icons[item.id] = candidates.lazy.compactMap(Self.icon).first
        }
    }

    private static func icon(of window: MenuBarHostWindow) -> Icon? {
        guard let image = capture(window.id), let content = contentBounds(of: image),
              let cropped = image.cropping(to: content)
        else { return nil }
        let scale = window.frame.width / CGFloat(image.width)
        return Icon(image: cropped, size: CGSize(width: content.width * scale, height: content.height * scale))
    }

    private static func capture(_ id: CGWindowID) -> CGImage? {
        // The array holds raw window numbers, not objects.
        var values: [UnsafeRawPointer?] = [UnsafeRawPointer(bitPattern: UInt(id))]
        guard let createImage, let array = CFArrayCreate(nil, &values, 1, nil) else { return nil }
        return createImage(.null, array, boundsIgnoreFraming)?.takeRetainedValue()
    }

    /// The drawn part, without the empty padding around it; `nil` for an empty picture.
    private static func contentBounds(of image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let isDrawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * bytesPerPixel, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard isDrawn else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * bytesPerPixel + 3] > minOpaqueAlpha {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
