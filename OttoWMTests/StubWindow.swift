import CoreGraphics

final class StubWindow: Window {
    let id: CGWindowID
    let tabCount: Int
    let appName: String
    let isStandard: Bool
    let isFullScreen: Bool
    let isMinimized: Bool
    var frame: CGRect {
        didSet { frameSetCount += 1 }
    }

    private(set) var frameSetCount = 0
    private(set) var focusCount = 0

    init(
        id: CGWindowID,
        tabCount: Int = 1,
        frame: CGRect,
        appName: String = "App",
        isMinimized: Bool = false,
        isStandard: Bool = true,
        isFullScreen: Bool = false
    ) {
        self.id = id
        self.tabCount = tabCount
        self.frame = frame
        self.appName = appName
        self.isMinimized = isMinimized
        self.isStandard = isStandard
        self.isFullScreen = isFullScreen
    }

    func focus() { focusCount += 1 }
}
