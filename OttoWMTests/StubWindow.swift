import CoreGraphics

final class StubWindow: Window {
    let id: CGWindowID
    let appName: String
    let tabCount: Int
    let isStandard: Bool
    var isFullScreen: Bool
    var isMinimized: Bool
    private(set) var frame: CGRect

    private(set) var frameSetCount = 0
    private(set) var focusCount = 0
    private(set) var movableFrameCount = 0

    init(
        id: CGWindowID,
        appName: String = "App",
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
        tabCount: Int = 1,
        isStandard: Bool = true,
        isFullScreen: Bool = false,
        isMinimized: Bool = false
    ) {
        self.id = id
        self.appName = appName
        self.frame = frame
        self.tabCount = tabCount
        self.isStandard = isStandard
        self.isFullScreen = isFullScreen
        self.isMinimized = isMinimized
    }

    func snapshot() -> WindowSnapshot {
        WindowSnapshot(
            id: id,
            appName: appName,
            isStandard: isStandard,
            isFullScreen: isFullScreen,
            isMinimized: isMinimized,
            tabCount: tabCount,
            frame: frame
        )
    }

    func movableFrame() -> CGRect? {
        movableFrameCount += 1
        return isMinimized ? nil : frame
    }

    func setFrame(_ frame: CGRect) {
        self.frame = frame
        frameSetCount += 1
    }

    func focus() { focusCount += 1 }
}
