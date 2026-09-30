import AppKit
import CoreGraphics

extension Screens {
    static let system = Screens {
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return [] }

        return screens.map { screen in
            Display(
                id: screen.displayID,
                fullFrame: screen.frame.flipped(primaryHeight: primaryHeight),
                visibleFrame: screen.visibleFrame.flipped(primaryHeight: primaryHeight)
            )
        }
    }
}

private extension NSScreen {
    var displayID: DisplayID {
        let number = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else {
            return DisplayID(rawValue: "display-\(number)")
        }
        return DisplayID(rawValue: CFUUIDCreateString(nil, uuid) as String)
    }
}
