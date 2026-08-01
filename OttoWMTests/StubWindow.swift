import CoreGraphics

final class StubWindow: Window {
    let id: CGWindowID
    let tabCount: Int
    let appName: String
    let isStandard: Bool
    var isFullScreen: Bool
    var isMinimized: Bool
    private(set) var frame: CGRect

    private(set) var frameSetCount = 0
    private(set) var focusCount = 0
    private(set) var movableFrameCount = 0

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
