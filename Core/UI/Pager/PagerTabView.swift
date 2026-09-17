import AppKit
import Metal

final class PagerTabView: SlidingView {
    private let number: RollingNumber

    init(number: RollingNumber = PagerTabView.badgeNumber()) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        self.number = number
        let size = PagerTab.size
        super.init(content: Self.tab(size: size, number: number), size: size, hiddenOffset: size)
        // `CALayer.filters` has no effect on macOS unless the view allows Core Image filters.
        layerUsesCoreImageFilters = true
    }

    private static func tab(size: CGSize, number: RollingNumber) -> CALayer {
        let shape = CAShapeLayer()
        shape.path = PagerTabShape.path(in: CGRect(origin: .zero, size: size))
        shape.fillColor = NSColor.black.cgColor

        let badge = CALayer()
        badge.frame = PagerTab.badge
        badge.backgroundColor = NSColor.white.cgColor
        badge.cornerRadius = 4
        badge.masksToBounds = true
        badge.addSublayer(number.layer)

        let tab = CALayer()
        tab.addSublayer(shape)
        tab.addSublayer(badge)
        return tab
    }

    private static func badgeNumber() -> RollingNumber {
        RollingNumber(
            value: 1,
            size: PagerTab.badge.size,
            font: .systemFont(ofSize: 12, weight: .bold),
            color: .black,
            duration: Pager.workspaceChangeDuration,
            // `MTLCreateSystemDefaultDevice` switches a dual GPU Mac to the discrete GPU, `MTLCopyAllDevices` does not.
            blurs: !MTLCopyAllDevices().isEmpty
        )
    }

    func show(workspace: Int) {
        guard isRevealed else { return number.set(workspace) }

        number.roll(to: workspace)
    }
}
