import QuartzCore

/// Moves a layer between its resting place and a hidden transform. The layer starts hidden.
/// Set the layer `frame` before creating it: `frame` is computed through the transform.
final class Transition {
    static let animationKey = "ottowm.transition"

    private let layer: CALayer
    private let hidden: CATransform3D
    private let duration: TimeInterval

    init(layer: CALayer, hidden: CATransform3D, duration: TimeInterval) {
        self.layer = layer
        self.hidden = hidden
        self.duration = duration

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = hidden
        CATransaction.commit()
    }

    func show() {
        move(to: CATransform3DIdentity, then: {})
    }

    /// `done` runs once the layer is hidden, or when a show interrupts the transition.
    func hide(then done: @escaping () -> Void) {
        move(to: hidden, then: done)
    }

    private func move(to transform: CATransform3D, then done: @escaping () -> Void) {
        let animation = CABasicAnimation(keyPath: "transform")
        // Starts from the on-screen value, so a show that interrupts a hide turns back without a jump.
        animation.fromValue = (layer.presentation() ?? layer).transform
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(done)
        layer.transform = transform
        layer.add(animation, forKey: Self.animationKey)
        CATransaction.commit()
    }
}
