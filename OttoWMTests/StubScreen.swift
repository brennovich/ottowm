import AppKit
import CoreGraphics

struct StubScreen: ScreenGeometry {
    var fullFrame: CGRect
    var visibleFrame: CGRect
}

extension StubScreen {
    static let standard = StubScreen(
        fullFrame: CGRect(x: 0, y: 0, width: 1792, height: 1120),
        visibleFrame: CGRect(x: 0, y: 38, width: 1792, height: 1082)
    )
}

func nubFrame(size: CGSize) -> CGRect {
    CGRect(origin: CGPoint(x: 1791, y: 1119), size: size)
}

extension NotificationCenter {
    func postNativeSpaceChange() {
        post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }
}
