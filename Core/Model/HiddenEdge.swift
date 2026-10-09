import CoreGraphics

struct HiddenEdge {
    private static let epsilon: CGFloat = 1
    private static let detectionMargin: CGFloat = 10

    private let display: Display

    init(display: Display) {
        self.display = display
    }

    func frame(parking windowFrame: CGRect) -> CGRect {
        let x = switch display.parkingCorner {
        case .bottomRight: display.fullFrame.maxX - Self.epsilon
        case .bottomLeft: display.fullFrame.minX - windowFrame.width + Self.epsilon
        }
        return CGRect(x: x, y: display.fullFrame.maxY - Self.epsilon, width: windowFrame.width, height: windowFrame.height)
    }

    func holds(_ frame: CGRect) -> Bool {
        switch display.parkingCorner {
        case .bottomRight: frame.minX >= display.fullFrame.maxX - Self.epsilon - Self.detectionMargin
        case .bottomLeft: frame.maxX <= display.fullFrame.minX + Self.epsilon + Self.detectionMargin
        }
    }
}
