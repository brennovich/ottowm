import CoreGraphics

/// The bottom-right sliver a parked window is moved to.
struct HiddenEdge {
    private static let epsilon: CGFloat = 1
    private static let detectionMargin: CGFloat = 10

    let screen: ScreenGeometry

    func frame(parking windowFrame: CGRect) -> CGRect {
        CGRect(
            x: screen.fullFrame.maxX - Self.epsilon,
            y: screen.fullFrame.maxY - Self.epsilon,
            width: windowFrame.width,
            height: windowFrame.height
        )
    }

    func holds(_ frame: CGRect) -> Bool {
        frame.minX >= screen.fullFrame.maxX - Self.epsilon - Self.detectionMargin
    }

    func recovered(from windowFrame: CGRect) -> CGRect {
        let visibleFrame = screen.visibleFrame
        let width = min(windowFrame.width, visibleFrame.width)
        let height = min(windowFrame.height, visibleFrame.height)

        return CGRect(
            x: visibleFrame.minX + (visibleFrame.width - width) / 2,
            y: visibleFrame.minY + (visibleFrame.height - height) / 2,
            width: width,
            height: height
        )
    }
}
