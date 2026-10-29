import Carbon.HIToolbox
import OSLog

/// System-wide shortcut via Carbon `RegisterEventHotKey`; needs no Accessibility permission.
/// Each instance needs a distinct `id`: every handler sees every hot key press and ignores foreign ones.
@MainActor
final class GlobalHotKey {
    nonisolated fileprivate static let signature: OSType = 0x4E48_4B59 // "NHKY"

    private let keyCode: UInt32
    private let modifiers: UInt32
    fileprivate let id: UInt32
    fileprivate let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "HotKey")

    init(keyCode: UInt32, modifiers: UInt32, id: UInt32 = 1, action: @escaping @MainActor () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.id = id
        self.action = action
    }

    func register() -> Bool {
        guard hotKeyRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                var pressedID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedID
                )
                guard status == noErr, pressedID.signature == GlobalHotKey.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let isMine = MainActor.assumeIsolated { pressedID.id == hotKey.id }
                guard isMine else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
        guard handlerStatus == noErr else {
            logger.error("InstallEventHandler failed: \(handlerStatus)")
            return false
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            logger.error("RegisterEventHotKey failed: \(registerStatus)")
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}
