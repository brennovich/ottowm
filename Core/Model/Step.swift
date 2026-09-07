import CoreGraphics

struct Step: Equatable {
    let direction: Direction
    let points: CGFloat

    func frame(moving frame: CGRect, within bounds: CGRect) -> CGRect {
        var origin = frame.origin

        switch direction {
        case .north:
            origin.y = max(frame.minY - points, min(bounds.minY, frame.minY))
        case .south:
            origin.y = min(frame.minY + points, max(bounds.maxY - frame.height, frame.minY))
        case .west:
            origin.x = max(frame.minX - points, min(bounds.minX, frame.minX))
        case .east:
            origin.x = min(frame.minX + points, max(bounds.maxX - frame.width, frame.minX))
        }

        return CGRect(origin: origin, size: frame.size)
    }
}
