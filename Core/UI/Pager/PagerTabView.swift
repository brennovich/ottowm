import AppKit
import Metal

/// The black tab with the workspace number in a white badge. Its badge frame is taken from the Hammerspoon Pager spoon.
final class PagerTabView: SlidingView {
    static let badge = CGRect(x: 28, y: 27, width: 20, height: 21)
    private static let rollDuration: TimeInterval = 0.3
    private static let pressDuration: TimeInterval = 0.1
    private static let pressedScale = CATransform3DMakeScale(0.94, 0.94, 1)

    private let number: RollingNumber
    let bodyLayer: CALayer
    let shapeLayer: CAShapeLayer
    let badgeLayer: CALayer
    var optionClicked: (() -> Void)?

    override var acceptsClicks: Bool { true }

    init(number: RollingNumber = PagerTabView.badgeNumber()) {
        self.number = number
        let (tab, bodyLayer, shapeLayer, badgeLayer) = CATransaction.withoutActions { Self.tab(number: number) }
        self.bodyLayer = bodyLayer
        self.shapeLayer = shapeLayer
        self.badgeLayer = badgeLayer
        super.init(content: tab, size: TabShape.size, hiddenOffset: TabShape.size)
        // `CALayer.filters` has no effect on macOS unless the view allows Core Image filters.
        layerUsesCoreImageFilters = true
    }

    /// The first click in a window that is not key is an activation click unless the view claims it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        press(true)
        guard event.modifierFlags.contains(.option) else { return }

        optionClicked?()
    }

    override func mouseUp(with event: NSEvent) {
        press(false)
    }

    func show(workspace: Int) {
        guard isRevealed else { return number.set(workspace) }

        number.roll(to: workspace)
    }

    override func toggle(_ retracted: Bool) {
        shapeLayer.transform = retracted ? TabShape.squeeze : CATransform3DIdentity
        badgeLayer.transform = retracted
            ? CATransform3DMakeTranslation(TabShape.size.width - Self.badge.minX, 0, 0)
            : CATransform3DIdentity
    }

    private func press(_ pressed: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.pressDuration)
        bodyLayer.transform = pressed ? Self.pressedScale : CATransform3DIdentity
        CATransaction.commit()
    }

    private static func tab(number: RollingNumber) -> (CALayer, CALayer, CAShapeLayer, CALayer) {
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

        let body = CALayer()
        // Anchored to the bottom right corner, the screen corner, so a scale shrinks the tab into it.
        body.bounds = CGRect(origin: .zero, size: TabShape.size)
        body.anchorPoint = CGPoint(x: 1, y: 1)
        body.position = CGPoint(x: TabShape.size.width, y: TabShape.size.height)
        body.addSublayer(shape)
        body.addSublayer(badgeLayer)

        let tab = CALayer()
        tab.addSublayer(body)
        return (tab, body, shape, badgeLayer)
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
