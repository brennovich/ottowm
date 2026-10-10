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
}
