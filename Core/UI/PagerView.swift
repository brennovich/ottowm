import SwiftUI

struct PagerView: View {
    let workspace: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            PagerTabShape().fill(Color.black)

            Text("\(workspace)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.black)
                .frame(width: PagerTab.badge.width, height: PagerTab.badge.height)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white))
                .offset(x: PagerTab.badge.minX, y: PagerTab.badge.minY)
        }
    }
}

struct PagerTabShape: Shape {
    private static let swoopWidth: CGFloat = 32
    private static let swoopHandleFraction: CGFloat = 0.75
    private static let shoulderHeightFraction: CGFloat = 0.25
    private static let cornerWidth: CGFloat = 24
    private static let cornerHandleFraction: CGFloat = 0.8

    func path(in rect: CGRect) -> Path {
        let shoulderY = rect.height * Self.shoulderHeightFraction
        let shoulderEndX = rect.width - Self.cornerWidth
        let swoopHandleX = Self.swoopWidth * Self.swoopHandleFraction

        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addCurve(
            to: CGPoint(x: Self.swoopWidth, y: shoulderY),
            control1: CGPoint(x: swoopHandleX, y: rect.height),
            control2: CGPoint(x: Self.swoopWidth - swoopHandleX, y: shoulderY)
        )
        path.addLine(to: CGPoint(x: shoulderEndX, y: shoulderY))
        path.addCurve(
            to: CGPoint(x: rect.width, y: 0),
            control1: CGPoint(x: shoulderEndX + Self.cornerWidth * Self.cornerHandleFraction, y: shoulderY),
            control2: CGPoint(x: rect.width, y: shoulderY * Self.cornerHandleFraction)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()

        return path
    }
}
