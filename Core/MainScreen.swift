import AppKit
import CoreGraphics

extension CGRect {
    /// The rect in OttoWM's top-left (AX) origin, y down space.
    ///
    /// Cocoa rects have a bottom-left origin with y up, measured against the primary
    /// display's height.
    func flippedToTopLeft(primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: origin.x,
            y: primaryHeight - origin.y - height,
            width: width,
            height: height
        )
    }
}

struct MainScreen: ScreenGeometry {
    var fullFrame: CGRect {
        screen.frame.flippedToTopLeft(primaryHeight: primaryHeight)
    }

    var visibleFrame: CGRect {
        screen.visibleFrame.flippedToTopLeft(primaryHeight: primaryHeight)
    }

    private var screen: NSScreen { NSScreen.main ?? NSScreen.screens[0] }

    private var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? screen.frame.height
    }
}
