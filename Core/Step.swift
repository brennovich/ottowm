import CoreGraphics

/// One move of a window across the desktop, in points.
struct Step: Equatable {
    let direction: Direction
    let points: CGFloat

    /// The frame the window lands on. The move stops at the edge of `bounds` it travels
    /// towards, and a window already past that edge stays where it is rather than jumping
    /// back inside. Only the axis the move travels changes.
    func frame(moving windowFrame: CGRect, within bounds: CGRect) -> CGRect {
        var origin = windowFrame.origin

        switch direction {
        case .north:
            origin.y = max(windowFrame.minY - points, min(bounds.minY, windowFrame.minY))
        case .south:
            origin.y = min(windowFrame.minY + points, max(bounds.maxY - windowFrame.height, windowFrame.minY))
        case .west:
            origin.x = max(windowFrame.minX - points, min(bounds.minX, windowFrame.minX))
        case .east:
            origin.x = min(windowFrame.minX + points, max(bounds.maxX - windowFrame.width, windowFrame.minX))
        }

        return CGRect(origin: origin, size: windowFrame.size)
    }
}
