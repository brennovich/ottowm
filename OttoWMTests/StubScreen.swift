import CoreGraphics

struct StubScreen: Screen {
    var fullFrame: CGRect
    var visibleFrame: CGRect
}

extension StubScreen {
    static let standard = StubScreen(
        fullFrame: CGRect(x: 0, y: 0, width: 1792, height: 1120),
        visibleFrame: CGRect(x: 0, y: 38, width: 1792, height: 1082)
    )
}
