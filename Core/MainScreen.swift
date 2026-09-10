import AppKit
import CoreGraphics

extension CGRect {
    func flippedToTopLeft(primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: origin.x,
            y: primaryHeight - origin.y - height,
            width: width,
            height: height
        )
    }
}

struct MainScreen: Screens {
    var main: Display? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height

        return Display(
            id: screen.displayID,
            fullFrame: screen.frame.flippedToTopLeft(primaryHeight: primaryHeight),
            visibleFrame: screen.visibleFrame.flippedToTopLeft(primaryHeight: primaryHeight)
        )
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
