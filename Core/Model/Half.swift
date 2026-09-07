import CoreGraphics

/// One side of a rect, taking half of it. The two halves of an axis leave `gap` between them,
/// so two windows, one in each half, cover exactly `bounds`.
struct Half {
    let direction: Direction

    func frame(within bounds: CGRect, gap: CGFloat) -> CGRect {
        let width = direction.isVertical ? bounds.width : (bounds.width - gap) / 2
        let height = direction.isVertical ? (bounds.height - gap) / 2 : bounds.height

        return CGRect(
            x: direction == .east ? bounds.maxX - width : bounds.minX,
            y: direction == .south ? bounds.maxY - height : bounds.minY,
            width: width,
            height: height
        )
    }
}
