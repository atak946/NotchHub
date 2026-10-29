import AppKit
import OSLog

/// Output volume and mute of the default output device; `onChange` fires on every CoreAudio update.
@MainActor
protocol HUDVolumeSource: AnyObject {
    var onChange: (@MainActor (HUDReading) -> Void)? { get set }
    func start()
    func stop()
    func currentReading() -> HUDReading?
}

/// Brightness / volume / keyboard-backlight key presses.
@MainActor
protocol HUDKeySource: AnyObject {
    var onKey: (@MainActor (SystemDefinedKeyEvent) -> Void)? { get set }
    func start()
    func stop()
}

/// Built-in display brightness 0…1, or `nil` when it cannot be read.
@MainActor
protocol HUDBrightnessReading {
    func brightness() -> Double?
}

/// Global + local `NSEvent` monitors for `.systemDefined` events.
@MainActor
final class SystemDefinedKeyMonitor: HUDKeySource {
    var onKey: (@MainActor (SystemDefinedKeyEvent) -> Void)?
    private var monitors: [Any] = []

    func start() {
        guard monitors.isEmpty else { return }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined, handler: { [weak self] event in
            let subtype = event.subtype.rawValue
            let data1 = event.data1
            MainActor.assumeIsolated { self?.handle(subtype: subtype, data1: data1) }
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined, handler: { [weak self] event in
            let subtype = event.subtype.rawValue
            let data1 = event.data1
            MainActor.assumeIsolated { self?.handle(subtype: subtype, data1: data1) }
            return event
        }) {
            monitors.append(monitor)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handle(subtype: Int16, data1: Int) {
        guard let event = SystemDefinedKeyEvent.decode(subtype: subtype, data1: data1) else { return }
        onKey?(event)
    }
}

/// Reads and sets the built-in display brightness through the private DisplayServices framework, loaded at runtime.
/// Missing framework or symbol → reads return `nil` (HUD without a level) and keys stay with macOS.
@MainActor
final class DisplayServicesBrightnessReader: HUDBrightnessReading {
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32

    private static let frameworkPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    private static let getSymbolName = "DisplayServicesGetBrightness"
    private static let setSymbolName = "DisplayServicesSetBrightness"

    private let getBrightness: GetBrightness?
    private let setBrightness: SetBrightness?
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "HUD")

    init() {
        guard let handle = dlopen(Self.frameworkPath, RTLD_LAZY) else {
            getBrightness = nil
            setBrightness = nil
            logger.notice("DisplayServices unavailable; brightness HUD shows without a level")
            return
        }
        // The handle stays open for the app's lifetime; the symbols must remain valid.
        if let symbol = dlsym(handle, Self.getSymbolName) {
            getBrightness = unsafeBitCast(symbol, to: GetBrightness.self)
        } else {
            getBrightness = nil
            logger.notice("DisplayServicesGetBrightness missing; brightness HUD shows without a level")
        }
        if let symbol = dlsym(handle, Self.setSymbolName) {
            setBrightness = unsafeBitCast(symbol, to: SetBrightness.self)
        } else {
            setBrightness = nil
            logger.notice("DisplayServicesSetBrightness missing; brightness keys stay with macOS")
        }
    }

    func brightness() -> Double? {
        guard let getBrightness, let displayID = Self.builtInDisplayID() else { return nil }
        var value: Float = 0
        let status = getBrightness(displayID, &value)
        guard status == 0, value.isFinite else { return nil }
        return HUDLevel.clamped(Double(value))
    }

    /// Brightness keys are only taken over when the level can be read back and written.
    var canSetBrightness: Bool {
        setBrightness != nil && brightness() != nil
    }

    /// Writes `level` (clamped to 0…1); `false` when unsupported or the call fails.
    @discardableResult
    func setBrightness(_ level: Double) -> Bool {
        guard let setBrightness, let displayID = Self.builtInDisplayID() else { return false }
        let status = setBrightness(displayID, Float(HUDLevel.clamped(level)))
        if status != 0 {
            logger.error("DisplayServicesSetBrightness failed: \(status)")
        }
        return status == 0
    }

    private static func builtInDisplayID() -> CGDirectDisplayID? {
        NSScreen.screens.first(where: \.isBuiltIn)?.displayID
    }
}
