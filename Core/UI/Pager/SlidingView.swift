import AppKit

/// A layer-hosting view whose content slides between the view bounds and a hidden offset. The content starts hidden.
/// It also retracts against the screen edge, which a subclass applies to its own layers.
/// The content and its sublayers use a top left origin.
class SlidingView: NSView {
    static let animationKey = "ottowm.slide"
    static let defaultDuration: TimeInterval = 0.3
    static let mirror = CATransform3DMakeScale(-1, 1, 1)

    private let content: CALayer
    private let flippedLayer = CALayer()
    private let hiddenTransform: CATransform3D
    private let duration: TimeInterval
    private(set) var isRevealed = false
    private(set) var isRetracted = false

    /// Whether the panel holding the view takes clicks on the drawn content. False: every click reaches the window under it.
    var acceptsClicks: Bool { false }

    /// Flips the content across its vertical centre: the slide, the retract and the shapes are drawn for the right screen
    /// edge, and land on the left one.
    var isMirrored = false {
        didSet {
            CATransaction.withoutActions { flippedLayer.sublayerTransform = isMirrored ? Self.mirror : CATransform3DIdentity }
        }
    }

    /// `hiddenOffset` is in top left coordinates.
    init(content: CALayer, size: CGSize, hiddenOffset: CGSize, duration: TimeInterval = defaultDuration) {
        let bounds = CGRect(origin: .zero, size: size)
        self.content = content
        self.duration = duration
        hiddenTransform = CATransform3DMakeTranslation(hiddenOffset.width, hiddenOffset.height, 0)
        super.init(frame: bounds)

        CATransaction.withoutActions {
            // The frame is computed through the transform, so it is set first.
            content.frame = bounds
            content.transform = hiddenTransform
            let root = CALayer()
            layer = root
            wantsLayer = true

            // AppKit resets the flip on the view's own layer, so it is set on a sublayer.
            flippedLayer.frame = bounds
            flippedLayer.isGeometryFlipped = true
            flippedLayer.addSublayer(content)
            root.addSublayer(flippedLayer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        setContentsScale(window?.backingScaleFactor ?? 1, in: content)
    }

    func reveal() {
        isRevealed = true
        slide(to: CATransform3DIdentity, then: {})
    }

    /// `done` runs once the content has slid out, or when a reveal interrupts the slide.
    func conceal(then done: @escaping () -> Void) {
        isRevealed = false
        slide(to: hiddenTransform, then: done)
    }

    /// The guard drops a repeat of the state the view is already in: applying it again restarts the animation mid slide.
    func retract() {
        guard !isRetracted else { return }

        isRetracted = true
        TabShape.retracting { toggle(true) }
    }

    func restore() {
        guard isRetracted else { return }

        isRetracted = false
        TabShape.retracting { toggle(false) }
    }

    /// Runs inside the retract transaction. The default does nothing: the corner masks never retract.
    func toggle(_ retracted: Bool) {}

    private func slide(to transform: CATransform3D, then done: @escaping () -> Void) {
        let animation = CABasicAnimation(keyPath: "transform")
        // Starts from the on-screen value, so a reveal that interrupts a conceal turns back without a jump.
        animation.fromValue = (content.presentation() ?? content).transform
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        CATransaction.withoutActions {
            CATransaction.setCompletionBlock(done)
            content.transform = transform
            content.add(animation, forKey: Self.animationKey)
        }
    }

    /// A mask is not a sublayer, so it is walked on its own: left at 1 it draws the edge it clips at half resolution on a 2x display.
    private func setContentsScale(_ scale: CGFloat, in layer: CALayer) {
        layer.contentsScale = scale
        if let mask = layer.mask {
            setContentsScale(scale, in: mask)
        }
        for sublayer in layer.sublayers ?? [] {
            setContentsScale(scale, in: sublayer)
        }
    }
}
