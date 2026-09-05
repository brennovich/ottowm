import CoreGraphics

struct HiddenEdge {
    private static let epsilon: CGFloat = 1
    private static let detectionMargin: CGFloat = 10

    private let screen: ScreenGeometry

    init(screen: ScreenGeometry) {
        self.screen = screen
    }

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
}
