import CoreGraphics

struct StubWindow: Window {
    var id: CGWindowID
    var tabCount: Int
    var frame: CGRect
    var appName: String
    var isStandard = true
    var isFullScreen = false
    var isMinimized = false

    func focus() {}
}
