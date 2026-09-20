import AppKit
import Metal

/// The black tab with the workspace number in a white badge. Its badge frame is taken from the Hammerspoon Pager spoon.
final class PagerTabView: SlidingView {
    static let badge = CGRect(x: 28, y: 27, width: 20, height: 21)
    private static let rollDuration: TimeInterval = 0.3

    private let number: RollingNumber
    let shapeLayer: CAShapeLayer
    let badgeLayer: CALayer
    private(set) var isRetracted = false

    init(number: RollingNumber = PagerTabView.badgeNumber()) {
        self.number = number
        let (tab, shapeLayer, badgeLayer) = CATransaction.withoutActions { Self.tab(number: number) }
        self.shapeLayer = shapeLayer
        self.badgeLayer = badgeLayer
        super.init(content: tab, size: TabShape.size, hiddenOffset: TabShape.size)
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
            shape: TabShape.squeeze,
            badge: CATransform3DMakeTranslation(TabShape.size.width - Self.badge.minX, 0, 0)
        )
    }

    func restore() {
        guard isRetracted else { return }

        isRetracted = false
        animate(shape: CATransform3DIdentity, badge: CATransform3DIdentity)
    }

    private func animate(shape: CATransform3D, badge: CATransform3D) {
        TabShape.retracting {
            shapeLayer.transform = shape
            badgeLayer.transform = badge
        }
    }

    private static func tab(number: RollingNumber) -> (CALayer, CAShapeLayer, CALayer) {
        let shape = CAShapeLayer()
        // Anchored to the right edge, so a scale keeps that edge on the screen edge.
        shape.bounds = CGRect(origin: .zero, size: TabShape.size)
        shape.anchorPoint = CGPoint(x: 1, y: 0.5)
        shape.position = CGPoint(x: TabShape.size.width, y: TabShape.size.height / 2)
        shape.path = TabShape.path(in: CGRect(origin: .zero, size: TabShape.size))
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
