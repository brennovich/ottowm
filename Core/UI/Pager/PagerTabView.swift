import AppKit
import Metal

/// The black tab with the workspace number in a white badge. Its size and badge frame are taken from the Hammerspoon Pager spoon.
final class PagerTabView: SlidingView {
    static let size = CGSize(width: 54, height: 58)
    static let badge = CGRect(x: 28, y: 27, width: 20, height: 21)
    private static let rollDuration: TimeInterval = 0.3
    private static let swoopWidth: CGFloat = 32
    private static let swoopHandleFraction: CGFloat = 0.75
    private static let shoulderHeightFraction: CGFloat = 0.25
    private static let cornerWidth: CGFloat = 24
    private static let cornerHandleFraction: CGFloat = 0.8

    private let number: RollingNumber

    init(number: RollingNumber = PagerTabView.badgeNumber()) {
        self.number = number
        super.init(content: CATransaction.withoutActions { Self.tab(number: number) }, size: Self.size, hiddenOffset: Self.size)
        // `CALayer.filters` has no effect on macOS unless the view allows Core Image filters.
        layerUsesCoreImageFilters = true
    }

    /// `screenFrame` is in AppKit coordinates. The bottom right corner is where `HiddenEdge` parks windows.
    static func frame(in screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.maxX - size.width, y: screenFrame.minY, width: size.width, height: size.height)
    }

    func show(workspace: Int) {
        guard isRevealed else { return number.set(workspace) }

        number.roll(to: workspace)
    }

    private static func tab(number: RollingNumber) -> CALayer {
        let shape = CAShapeLayer()
        shape.path = path(in: CGRect(origin: .zero, size: size))
        shape.fillColor = NSColor.black.cgColor

        let badgeLayer = CALayer()
        badgeLayer.frame = badge
        badgeLayer.backgroundColor = NSColor.white.cgColor
        badgeLayer.cornerRadius = 4
        badgeLayer.masksToBounds = true
        badgeLayer.addSublayer(number.layer)

        let tab = CALayer()
        tab.addSublayer(shape)
        tab.addSublayer(badgeLayer)
        return tab
    }

    private static func path(in rect: CGRect) -> CGPath {
        let shoulderY = rect.height * shoulderHeightFraction
        let shoulderEndX = rect.width - cornerWidth
        let swoopHandleX = swoopWidth * swoopHandleFraction

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addCurve(
            to: CGPoint(x: swoopWidth, y: shoulderY),
            control1: CGPoint(x: swoopHandleX, y: rect.height),
            control2: CGPoint(x: swoopWidth - swoopHandleX, y: shoulderY)
        )
        path.addLine(to: CGPoint(x: shoulderEndX, y: shoulderY))
        path.addCurve(
            to: CGPoint(x: rect.width, y: 0),
            control1: CGPoint(x: shoulderEndX + cornerWidth * cornerHandleFraction, y: shoulderY),
            control2: CGPoint(x: rect.width, y: shoulderY * cornerHandleFraction)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }

    private static func badgeNumber() -> RollingNumber {
        RollingNumber(
            value: 1,
            size: badge.size,
            font: .systemFont(ofSize: 12, weight: .bold),
            color: .black,
            duration: rollDuration,
            // `MTLCreateSystemDefaultDevice` switches a dual GPU Mac to the discrete GPU, `MTLCopyAllDevices` does not.
            blurs: !MTLCopyAllDevices().isEmpty
        )
    }
}
