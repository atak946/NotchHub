import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value
    }

    var isBuiltIn: Bool {
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    var notchGeometry: NotchGeometry {
        NotchGeometry.make(
            screenFrame: frame,
            safeAreaTop: safeAreaInsets.top,
            leftAuxiliaryWidth: auxiliaryTopLeftArea?.width,
            rightAuxiliaryWidth: auxiliaryTopRightArea?.width,
            menuBarHeight: frame.maxY - visibleFrame.maxY
        )
    }

    static func screen(containing point: CGPoint) -> NSScreen? {
        screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}
