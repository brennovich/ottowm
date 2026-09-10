import AppKit
import CoreGraphics

final class StubScreen: Screens {
    var main: Display?

    init(main: Display?) {
        self.main = main
    }
}

extension Display {
    static let standard = Display(
        id: DisplayID(rawValue: "built-in"),
        fullFrame: CGRect(x: 0, y: 0, width: 1792, height: 1120),
        visibleFrame: CGRect(x: 0, y: 38, width: 1792, height: 1082)
    )

    static let external = Display(
        id: DisplayID(rawValue: "external"),
        fullFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 0, y: 25, width: 2560, height: 1415)
    )
}

func hiddenEdgeFrame(size: CGSize, on display: Display = .standard) -> CGRect {
    CGRect(origin: CGPoint(x: display.fullFrame.maxX - 1, y: display.fullFrame.maxY - 1), size: size)
}

extension NotificationCenter {
    func postNativeSpaceChange() {
        post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }
}
