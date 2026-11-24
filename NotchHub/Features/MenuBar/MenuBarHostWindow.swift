import CoreGraphics
import Foundation

/// The window server window that draws an icon. Control Center owns it, not the icon's app.
struct MenuBarHostWindow: Sendable {
    private static let statusItemLayer = 25
    private static let horizontalTolerance: CGFloat = 4
    private static let verticalTolerance: CGFloat = 14

    let id: CGWindowID
    let ownerPID: pid_t
    let frame: CGRect
    /// The app's bundle identifier on the built-in display; only readable with Screen Recording access.
    let name: String?

    /// Every icon on every display, hidden ones included.
    static func all() -> [MenuBarHostWindow] {
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == statusItemLayer,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            return MenuBarHostWindow(id: id, ownerPID: pid, frame: frame, name: info[kCGWindowName as String] as? String)
        }
    }

    /// Apps report a frame a few points off the window's, but share its center.
    func hosts(_ itemFrame: CGRect) -> Bool {
        abs(frame.midX - itemFrame.midX) < Self.horizontalTolerance
            && abs(frame.midY - itemFrame.midY) < Self.verticalTolerance
    }
}
