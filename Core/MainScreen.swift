import AppKit
import CoreGraphics

// Flips a Cocoa rect (bottom-left origin, y up) into OttoWM's top-left (AX)
// origin, y down space against the primary display's height.
func topLeftFrame(fromCocoa cocoaFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
    CGRect(
        x: cocoaFrame.origin.x,
        y: primaryHeight - cocoaFrame.origin.y - cocoaFrame.height,
        width: cocoaFrame.width,
        height: cocoaFrame.height
    )
}

struct MainScreen: Screen {
    var fullFrame: CGRect {
        topLeftFrame(fromCocoa: screen.frame, primaryHeight: primaryHeight)
    }

    var visibleFrame: CGRect {
        topLeftFrame(fromCocoa: screen.visibleFrame, primaryHeight: primaryHeight)
    }

    private var screen: NSScreen { NSScreen.main ?? NSScreen.screens[0] }

    private var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? screen.frame.height
    }
}
