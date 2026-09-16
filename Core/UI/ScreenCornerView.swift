import SwiftUI

struct ScreenCornerView: View {
    let corner: ScreenCorner

    var body: some View {
        ScreenCornerShape()
            .fill(Color.black)
            .rotationEffect(corner.rotation)
    }
}

/// The part of a square outside the quarter circle centered on its bottom right point.
struct ScreenCornerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.addRelativeArc(
            center: CGPoint(x: rect.width, y: rect.height),
            radius: rect.width,
            startAngle: .degrees(180),
            delta: .degrees(90)
        )
        path.closeSubpath()
        return path
    }
}
