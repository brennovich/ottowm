import CoreGraphics

struct HiddenEdge {
    private static let epsilon: CGFloat = 1
    private static let detectionMargin: CGFloat = 10

    private let display: Display

    init(display: Display) {
        self.display = display
    }

    func frame(parking windowFrame: CGRect) -> CGRect {
        CGRect(
            x: display.fullFrame.maxX - Self.epsilon,
            y: display.fullFrame.maxY - Self.epsilon,
            width: windowFrame.width,
            height: windowFrame.height
        )
    }

    func holds(_ frame: CGRect) -> Bool {
        frame.minX >= display.fullFrame.maxX - Self.epsilon - Self.detectionMargin
    }
}
