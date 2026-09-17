import AppKit

/// A layer-hosting view whose content slides between the view bounds and a hidden offset. The content starts hidden.
/// The content and its sublayers use a top left origin.
class SlidingView: NSView {
    static let animationKey = "ottowm.slide"

    private let content: CALayer
    private let hiddenTransform: CATransform3D
    private let duration: TimeInterval
    private(set) var isRevealed = false

    /// `hiddenOffset` is in top left coordinates.
    init(content: CALayer, size: CGSize, hiddenOffset: CGSize, duration: TimeInterval = 0.3) {
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
            let flipped = CALayer()
            flipped.frame = bounds
            flipped.isGeometryFlipped = true
            flipped.addSublayer(content)
            root.addSublayer(flipped)
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

    private func setContentsScale(_ scale: CGFloat, in layer: CALayer) {
        layer.contentsScale = scale
        for sublayer in layer.sublayers ?? [] {
            setContentsScale(scale, in: sublayer)
        }
    }
}
