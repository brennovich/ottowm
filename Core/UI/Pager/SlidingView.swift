import AppKit

/// A layer-hosting view whose content slides between the view bounds and a hidden offset.
/// The content and its sublayers use a top left origin.
class SlidingView: NSView {
    private let content: CALayer
    private let slide: Transition
    private(set) var isRevealed = false

    /// `hiddenOffset` is in top left coordinates.
    init(content: CALayer, size: CGSize, hiddenOffset: CGSize) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let bounds = CGRect(origin: .zero, size: size)
        content.frame = bounds
        self.content = content
        slide = Transition(
            layer: content,
            hidden: CATransform3DMakeTranslation(hiddenOffset.width, hiddenOffset.height, 0),
            duration: Pager.transitionDuration
        )
        super.init(frame: bounds)
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
        slide.show()
    }

    /// `done` runs once the content has slid out, or when a reveal interrupts the slide.
    func conceal(then done: @escaping () -> Void) {
        isRevealed = false
        slide.hide(then: done)
    }

    private func setContentsScale(_ scale: CGFloat, in layer: CALayer) {
        layer.contentsScale = scale
        for sublayer in layer.sublayers ?? [] {
            setContentsScale(scale, in: sublayer)
        }
    }
}
