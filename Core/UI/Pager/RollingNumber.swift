import AppKit

/// A number that rolls to a new value, modelled on SwiftUI's `numericText`: the old value leaves while the new one
/// enters, both offset, blurred and scaled down. The blur needs `layerUsesCoreImageFilters` on the hosting view.
final class RollingNumber {
    static let distance: CGFloat = 7
    static let animationKey = "ottowm.roll"
    private static let blurRadius: CGFloat = 1.5
    private static let scale: CGFloat = 0.8
    private static let timing = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)

    let layer = CALayer()
    private let number = CATextLayer()
    private let leavingNumber = CATextLayer()
    private let duration: TimeInterval
    private var value: Int

    init(value: Int, size: CGSize, font: NSFont, color: NSColor, duration: TimeInterval) {
        self.value = value
        self.duration = duration

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = CGRect(origin: .zero, size: size)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        for text in [number, leavingNumber] {
            text.frame = CGRect(x: 0, y: (size.height - lineHeight) / 2, width: size.width, height: lineHeight)
            text.font = font
            text.fontSize = font.pointSize
            text.foregroundColor = color.cgColor
            text.alignmentMode = .center
            text.filters = [Self.blur()]
            // The new string is drawn when the outermost open transaction commits. If that transaction
            // allows actions, it adds a `contents` crossfade from the old digit to the new one.
            text.actions = ["contents": NSNull()]
            layer.addSublayer(text)
        }
        number.string = "\(value)"
        leavingNumber.opacity = 0
        CATransaction.commit()
    }

    func set(_ value: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        number.string = "\(value)"
        CATransaction.commit()
        self.value = value
    }

    func roll(to value: Int) {
        // In a flipped layer tree a negative offset is above.
        let entryOffset = value > self.value ? -Self.distance : Self.distance

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        leavingNumber.string = number.string
        number.string = "\(value)"
        leavingNumber.add(rollAnimation(from: .resting, to: .away(by: -entryOffset)), forKey: Self.animationKey)
        number.add(rollAnimation(from: .away(by: entryOffset), to: .resting), forKey: Self.animationKey)
        CATransaction.commit()
        self.value = value
    }

    private static func blur() -> CIFilter {
        let blur = CIFilter(name: "CIGaussianBlur")!
        blur.name = "blur"
        blur.setValue(0, forKey: kCIInputRadiusKey)
        return blur
    }

    private struct State {
        let offset: CGFloat
        let opacity: Float
        let blurRadius: CGFloat
        let scale: CGFloat

        static let resting = State(offset: 0, opacity: 1, blurRadius: 0, scale: 1)

        static func away(by offset: CGFloat) -> State {
            State(offset: offset, opacity: 0, blurRadius: RollingNumber.blurRadius, scale: RollingNumber.scale)
        }

        var transform: CATransform3D {
            CATransform3DScale(CATransform3DMakeTranslation(0, offset, 0), scale, scale, 1)
        }
    }

    /// The layer shows its own values once the animation ends: the new number rests, the leaving one has opacity 0.
    private func rollAnimation(from start: State, to end: State) -> CAAnimation {
        let group = CAAnimationGroup()
        group.animations = [
            Self.basicAnimation("transform", from: start.transform, to: end.transform),
            Self.basicAnimation("opacity", from: start.opacity, to: end.opacity),
            Self.basicAnimation("filters.blur.inputRadius", from: start.blurRadius, to: end.blurRadius),
        ]
        group.duration = duration
        group.timingFunction = Self.timing
        return group
    }

    private static func basicAnimation(_ keyPath: String, from start: Any, to end: Any) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = start
        animation.toValue = end
        return animation
    }
}
