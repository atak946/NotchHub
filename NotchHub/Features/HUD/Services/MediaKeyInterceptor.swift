import AppKit
import CoreGraphics
import OSLog

/// Active session event tap on `NX_SYSDEFINED` events, installed on the main run loop.
/// Swallowed volume/brightness keys never reach macOS, so its own HUD stays hidden.
@MainActor
final class MediaKeyInterceptor: MediaKeyTapping {
    /// `NX_SYSDEFINED`; not exposed as a `CGEventType` case.
    nonisolated static let systemDefinedEventType: UInt32 = 14

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "HUD")
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var context: Unmanaged<MediaKeyTapContext>?

    var isInstalled: Bool { port != nil }

    func install(handler: @escaping MediaKeyTapHandler) -> Bool {
        guard port == nil else { return true }
        let tapContext = MediaKeyTapContext(handler: handler)
        let unmanaged = Unmanaged.passRetained(tapContext)
        let mask = CGEventMask(1) << CGEventMask(Self.systemDefinedEventType)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mediaKeyTapCallback,
            userInfo: unmanaged.toOpaque()
        ) else {
            unmanaged.release()
            logger.error("Creating the media key event tap failed")
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            unmanaged.release()
            logger.error("Creating the media key run loop source failed")
            return false
        }
        tapContext.port = port
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        context = unmanaged
        return true
    }

    func remove() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(port)
        // Safe: the callback only runs on the main run loop, which is executing this method.
        context?.takeUnretainedValue().port = nil
        context?.release()
        context = nil
        source = nil
        self.port = nil
    }
}

/// Retained by the tap as its `userInfo`; reached from the C callback on the main thread.
@MainActor
final class MediaKeyTapContext {
    let handler: MediaKeyTapHandler
    var port: CFMachPort?
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "HUD")

    init(handler: @escaping MediaKeyTapHandler) {
        self.handler = handler
    }

    /// macOS disables a tap that is too slow or after secure input; turn it straight back on.
    func reenable() {
        guard let port else { return }
        logger.notice("Media key tap was disabled by the system; re-enabling")
        CGEvent.tapEnable(tap: port, enable: true)
    }
}

/// C callback; must stay fast. Anything that is not a decodable aux-button event passes through untouched.
private func mediaKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let passThrough = Unmanaged.passUnretained(event)
    guard let userInfo else { return passThrough }
    let context = Unmanaged<MediaKeyTapContext>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { context.reenable() }
        return passThrough
    }
    guard type.rawValue == MediaKeyInterceptor.systemDefinedEventType,
          let nsEvent = NSEvent(cgEvent: event),
          let decoded = SystemDefinedKeyEvent.decode(subtype: nsEvent.subtype.rawValue, data1: nsEvent.data1)
    else { return passThrough }
    let isFine = MediaKeyPolicy.isFineModifier(event.flags)
    let consume = MainActor.assumeIsolated { context.handler(decoded, isFine) }
    return consume ? nil : passThrough
}
