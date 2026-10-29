import Carbon.HIToolbox
import Observation
import OSLog

/// Registers ⌥⌘M for the microphone mute while `MicMuteController.isHotKeyEnabled` is on.
@MainActor
final class MicMuteHotKey {
    /// Distinct from the panel hot key (id 1).
    static let hotKeyID: UInt32 = 2
    static let displayName = "⌥⌘M"

    private let controller: MicMuteController
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "MicMute")
    private var hotKey: GlobalHotKey?
    private var isStarted = false

    init(controller: MicMuteController) {
        self.controller = controller
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        applySetting()
    }

    func stop() {
        isStarted = false
        hotKey?.unregister()
        hotKey = nil
    }

    private func applySetting() {
        let isEnabled = withObservationTracking {
            controller.isHotKeyEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isStarted else { return }
                self.applySetting()
            }
        }
        isEnabled ? register() : unregister()
    }

    private func register() {
        guard hotKey == nil else { return }
        let hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_M),
            modifiers: UInt32(cmdKey | optionKey),
            id: Self.hotKeyID
        ) { [weak controller] in
            controller?.toggle()
        }
        guard hotKey.register() else {
            logger.error("Failed to register global hot key \(Self.displayName, privacy: .public)")
            return
        }
        self.hotKey = hotKey
    }

    private func unregister() {
        hotKey?.unregister()
        hotKey = nil
    }
}
