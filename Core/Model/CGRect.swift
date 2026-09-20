import CoreGraphics

extension CGRect {
    /// Converts between AppKit's bottom left coordinates and top left coordinates. The flip is
    /// its own inverse.
    func flipped(primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: origin.x,
            y: primaryHeight - origin.y - height,
            width: width,
            height: height
        )
    }

    /// The rect of `size` with the same bottom right corner as this one, which is the screen corner in
    /// top left coordinates. It is not clamped: a larger `size` reaches past this rect's top left.
    func bottomRight(size: CGSize) -> CGRect {
        CGRect(x: maxX - size.width, y: maxY - size.height, width: size.width, height: size.height)
    }
}
