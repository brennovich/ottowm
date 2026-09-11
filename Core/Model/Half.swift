import CoreGraphics

/// The half of `bounds` on the side `direction` names, which is where a fill sends a window:
/// north and south split the height and keep the full width, east and west split the width.
/// The two halves stay `gap` apart, each giving up half of it.
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
