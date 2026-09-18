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
    /// Covers the parked windows' 1px slivers; their 30pt shadow shows past it. At spacing 20 a maximized window ends where it starts.
    private static let retractedWidth: CGFloat = 20
    private static let retractDuration: TimeInterval = 0.2

    private let number: RollingNumber
    let shapeLayer: CAShapeLayer
    let badgeLayer: CALayer
    private(set) var isRetracted = false

    init(number: RollingNumber = PagerTabView.badgeNumber()) {
        self.number = number
        let (tab, shapeLayer, badgeLayer) = CATransaction.withoutActions { Self.tab(number: number) }
        self.shapeLayer = shapeLayer
        self.badgeLayer = badgeLayer
        super.init(content: tab, size: Self.size, hiddenOffset: Self.size)
        // `CALayer.filters` has no effect on macOS unless the view allows Core Image filters.
        layerUsesCoreImageFilters = true
    }

    func show(workspace: Int) {
        guard isRevealed else { return number.set(workspace) }

        number.roll(to: workspace)
    }

    /// Squeezes the shape against the screen edge and moves the badge past it.
    func retract() {
        guard !isRetracted else { return }

        isRetracted = true
        animate(
            shape: CATransform3DMakeScale(Self.retractedWidth / Self.size.width, 1, 1),
            badge: CATransform3DMakeTranslation(Self.size.width - Self.badge.minX, 0, 0)
        )
    }

    func restore() {
        guard isRetracted else { return }

        isRetracted = false
        animate(shape: CATransform3DIdentity, badge: CATransform3DIdentity)
    }

    /// The implicit actions start from the on-screen value, so a restore during a retract turns back without a jump.
    private func animate(shape: CATransform3D, badge: CATransform3D) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.retractDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        shapeLayer.transform = shape
        badgeLayer.transform = badge
        CATransaction.commit()
    }

    private static func tab(number: RollingNumber) -> (CALayer, CAShapeLayer, CALayer) {
        let shape = CAShapeLayer()
        // Anchored to the right edge, so a scale keeps that edge on the screen edge.
        shape.bounds = CGRect(origin: .zero, size: size)
        shape.anchorPoint = CGPoint(x: 1, y: 0.5)
        shape.position = CGPoint(x: size.width, y: size.height / 2)
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
        return (tab, shape, badgeLayer)
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
