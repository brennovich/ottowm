import AppKit

final class ScreenCornerView: SlidingView {
    init(corner: ScreenCorner, radius: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let mask = CAShapeLayer()
        mask.path = corner.mask(radius: radius)
        mask.fillColor = NSColor.black.cgColor
        super.init(content: mask, size: CGSize(width: radius, height: radius), hiddenOffset: corner.hiddenOffset(radius: radius))
    }
}
