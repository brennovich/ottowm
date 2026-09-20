import QuartzCore

/// The geometry of the pager tab and how it retracts, used by the tab itself and by the cue that spreads from it.
/// The size and the curves are taken from the Hammerspoon Pager spoon.
enum TabShape {
    static let size = CGSize(width: 54, height: 58)
    /// Squeezes the shape against its right edge, which is the screen edge.
    static let squeeze = CATransform3DMakeScale(retractedWidth / size.width, 1, 1)

    /// Covers the parked windows' 1px slivers; their 30pt shadow shows past it. At spacing 20 a maximized window ends where it starts.
    private static let retractedWidth: CGFloat = 20
    private static let retractDuration: TimeInterval = 0.2

    private static let swoopWidth: CGFloat = 32
    private static let swoopHandleFraction: CGFloat = 0.75
    private static let shoulderHeightFraction: CGFloat = 0.25
    private static let cornerWidth: CGFloat = 24
    private static let cornerHandleFraction: CGFloat = 0.8

    /// The implicit actions start from the on-screen value, so a restore during a retract turns back without a jump.
    static func retracting(_ apply: () -> Void) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(retractDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        apply()
        CATransaction.commit()
    }

    static func path(in rect: CGRect) -> CGPath {
        let shoulderY = rect.height * shoulderHeightFraction
        let shoulderEndX = rect.width - cornerWidth
        let swoopHandleX = swoopWidth * swoopHandleFraction

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addCurve(
            to: CGPoint(x: swoopWidth, y: shoulderY),
            control1: CGPoint(x: swoopHandleX, y: rect.height),
            control2: CGPoint(x: swoopWidth - swoopHandleX, y: shoulderY)
        )
        path.addLine(to: CGPoint(x: shoulderEndX, y: shoulderY))
        path.addCurve(
            to: CGPoint(x: rect.width, y: 0),
            control1: CGPoint(x: shoulderEndX + cornerWidth * cornerHandleFraction, y: shoulderY),
            control2: CGPoint(x: rect.width, y: shoulderY * cornerHandleFraction)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}
