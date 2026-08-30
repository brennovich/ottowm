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
