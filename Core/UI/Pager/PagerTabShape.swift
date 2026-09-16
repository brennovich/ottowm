import CoreGraphics

enum PagerTabShape {
    private static let swoopWidth: CGFloat = 32
    private static let swoopHandleFraction: CGFloat = 0.75
    private static let shoulderHeightFraction: CGFloat = 0.25
    private static let cornerWidth: CGFloat = 24
    private static let cornerHandleFraction: CGFloat = 0.8

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
