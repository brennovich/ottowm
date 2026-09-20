import AppKit

/// Copies of the tab shape rising from under the tab, spreading past it and fading, running as long as the flag stays set:
///   - Red: the cue that an app holds secure event input, where no binding works.
final class CueView: SlidingView {
    /// Rounded up, since `NSWindow` rounds a fractional content size up: a ring anchored at the fractional
    /// size would land inside the panel and leave a gap against the screen edge.
    static let size = CGSize(
        width: (TabShape.size.width * reach).rounded(.up),
        height: (TabShape.size.height * reach).rounded(.up)
    )
    static let pulseKey = "ottowm.pulse"

    /// Where a ring starts, as a share of the tab. Under 1 it starts hidden behind the tab, which is opaque and one
    /// window level above, so its fade in is never seen.
    private static let startScale: CGFloat = 0.75
    /// Where a ring ends, as a share of the tab.
    private static let reach: CGFloat = 1.35
    private static let ringCount = 3
    private static let period: TimeInterval = 3
    /// The share of the period a ring spends under the tab. The keyframes turn here, so a ring is at full opacity
    /// exactly when it leaves the tab's outline and fades only while it travels outward.
    private static let emergeShare = 0.2
    private static let lineWidth: CGFloat = 1
    private static let drawnWidth = lineWidth * 2

    let rings: CAReplicatorLayer
    let ring: CAShapeLayer
    private(set) var isRetracted = false

    init() {
        let (cue, rings, ring) = CATransaction.withoutActions { Self.cue() }
        self.rings = rings
        self.ring = ring
        super.init(content: cue, size: Self.size, hiddenOffset: Self.size)
    }

    /// A reveal that interrupts a slide out leaves the running pulse alone, so it does not restart mid ring.
    override func reveal() {
        super.reveal()
        guard ring.animation(forKey: Self.pulseKey) == nil else { return }

        ring.add(Self.pulse(), forKey: Self.pulseKey)
    }

    /// The pulse ends only once the cue is off screen: `SlidingView` runs the completion early when a reveal interrupts
    /// the slide, and ending it there would leave the cue on screen with no rings until the next change of the flag.
    override func conceal(then done: @escaping () -> Void) {
        super.conceal { [weak self] in
            if let self, !self.isRevealed {
                self.ring.removeAnimation(forKey: Self.pulseKey)
            }
            done()
        }
    }

    func retract() {
        guard !isRetracted else { return }

        isRetracted = true
        TabShape.retracting { rings.transform = TabShape.squeeze }
    }

    func restore() {
        guard isRetracted else { return }

        isRetracted = false
        TabShape.retracting { rings.transform = CATransform3DIdentity }
    }

    private static func cue() -> (CALayer, CAReplicatorLayer, CAShapeLayer) {
        let bounds = CGRect(origin: .zero, size: TabShape.size)
        let path = TabShape.path(in: bounds)

        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = path
        mask.fillColor = NSColor.black.cgColor

        let ring = CAShapeLayer()
        ring.bounds = bounds
        // Anchored to the bottom right corner, the screen corner, so a scale grows the ring away from it.
        ring.anchorPoint = CGPoint(x: 1, y: 1)
        ring.position = CGPoint(x: bounds.maxX, y: bounds.maxY)
        ring.path = path
        ring.fillColor = NSColor(srgbRed: 226 / 255, green: 35 / 255, blue: 42 / 255, alpha: 0.82).cgColor
        ring.strokeColor = NSColor.black.withAlphaComponent(0.35).cgColor
        ring.lineWidth = drawnWidth
        ring.mask = mask
        // The model value draws nothing, so removing the pulse leaves nothing on screen.
        ring.opacity = 0

        let rings = CAReplicatorLayer()
        // The tab's bounds, not the panel's, so the retract squeezes it to the tab's retracted frame. It does not clip.
        rings.bounds = bounds
        rings.anchorPoint = CGPoint(x: 1, y: 1)
        rings.position = CGPoint(x: Self.size.width, y: Self.size.height)
        rings.instanceCount = ringCount
        rings.instanceDelay = period / Double(ringCount)
        rings.addSublayer(ring)

        let cue = CALayer()
        cue.addSublayer(rings)
        return (cue, rings, ring)
    }

    /// The first leg is linear and the second eases out, so a ring slows as it fades.
    private static func pulse() -> CAAnimationGroup {
        let scale = CAKeyframeAnimation(keyPath: "transform")
        scale.values = [startScale, 1, reach].map { CATransform3DMakeScale($0, $0, 1) }

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 0]

        // Held at `lineWidth` on screen while the ring grows.
        let width = CAKeyframeAnimation(keyPath: "lineWidth")
        width.values = [drawnWidth / startScale, drawnWidth, drawnWidth / reach]

        let group = CAAnimationGroup()
        group.animations = [scale, opacity, width].map {
            $0.keyTimes = [0, NSNumber(value: emergeShare), 1]
            $0.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut)]
            $0.duration = period
            return $0
        }
        group.duration = period
        group.repeatCount = .infinity
        return group
    }
}
