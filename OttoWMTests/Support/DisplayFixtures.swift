import AppKit
import CoreGraphics

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

    /// Right of `standard`.
    static let right = Display(
        id: DisplayID(rawValue: "right"),
        fullFrame: CGRect(x: 1792, y: -139, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1792, y: -114, width: 1920, height: 1055)
    )

    /// `right` moved down, its bottom 61pt below the bottom of `standard`.
    static let rightBelowTheCorner = Display(
        id: Display.right.id,
        fullFrame: CGRect(x: 1792, y: 101, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1792, y: 126, width: 1920, height: 1055)
    )

    func parking(at corner: ParkingCorner) -> Display {
        var display = self
        display.parkingCorner = corner
        return display
    }
}

func hiddenEdgeFrame(size: CGSize, on display: Display = .standard) -> CGRect {
    CGRect(origin: CGPoint(x: display.fullFrame.maxX - 1, y: display.fullFrame.maxY - 1), size: size)
}

extension NotificationCenter {
    func postNativeSpaceChange() {
        post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }
}
