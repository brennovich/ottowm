import AppKit
import Metal

/// The tab with the workspace number in a badge, in one of two styles:
/// - `system` draws the tab with the system material. AppKit draws the material opaque while Reduce Transparency is on.
/// - `classic` draws the tab black with a white badge.
final class PagerTabView: SlidingView {
    /// Picked by eye from captures. Nearest gaps: top edge 11.3pt, bottom 10pt, curve 7.6pt, right edge 8pt.
    static let badge = CGRect(x: 26, y: 27, width: 20, height: 21)
    private static let rollDuration: TimeInterval = 0.3
    private static let pressDuration: TimeInterval = 0.1
    private static let pressedScale = CATransform3DMakeScale(0.94, 0.94, 1)

    private let number: RollingNumber
    let bodyLayer: CALayer
    let shapeLayer: CAShapeLayer
    let badgeLayer: CALayer
    private let material = NSVisualEffectView()
    var style = Config.PagerStyle.system {
        didSet { applyStyle() }
    }
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
        addMaterial()
        applyStyle()
    }

    var materialLayer: CALayer? { material.layer }

    /// The material is a subview so AppKit keeps it in step with the appearance, but its layer is moved under the
    /// shape layer so it takes the slide, the press and the squeeze. The subview would otherwise take the clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStyle()
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

    private func addMaterial() {
        material.material = .menu
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.frame = CGRect(origin: .zero, size: TabShape.size)
        addSubview(material)
    }

    /// AppKit adds the material's layer to the view's own layer in the first display of a new window, and leaves it
    /// alone after that. The display is run here so the layer is moved once it is done.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.displayIfNeeded()
        guard let layer = material.layer, layer.superlayer !== shapeLayer else { return }

        CATransaction.withoutActions {
            layer.removeFromSuperlayer()
            layer.frame = CGRect(origin: .zero, size: TabShape.size)
            let mask = CAShapeLayer()
            mask.frame = layer.bounds
            mask.path = TabShape.path(in: layer.bounds)
            layer.mask = mask
            shapeLayer.addSublayer(layer)
        }
    }

    private func applyStyle() {
        let classic = style == .classic
        let lightMaterial = !classic && effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        CATransaction.withoutActions {
            material.layer?.isHidden = classic
            shapeLayer.fillColor = classic ? NSColor.black.cgColor : nil
            badgeLayer.backgroundColor = (lightMaterial ? NSColor.black : .white).cgColor
        }
        number.setColor(lightMaterial ? .white : .black)
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

        let badgeLayer = CALayer()
        badgeLayer.frame = badge
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
