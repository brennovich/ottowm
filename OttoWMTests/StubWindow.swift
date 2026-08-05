import CoreGraphics

final class StubWindow: Window {
    let id: CGWindowID
    let appName: String
    let tabs: Int
    let isStandard: Bool
    var isFullScreen: Bool
    var isMinimized: Bool
    private(set) var frame: CGRect

    private(set) var positionSetCount = 0
    private(set) var sizeSetCount = 0
    private(set) var focusCount = 0
    private(set) var movableFrameCount = 0
    private(set) var tabCountReadCount = 0

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
        self.tabs = tabCount
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
            frame: frame
        )
    }

    func tabCount() -> Int {
        tabCountReadCount += 1
        return tabs
    }

    func movableFrame() -> CGRect? {
        movableFrameCount += 1
        return isMinimized ? nil : frame
    }

    func setPosition(_ origin: CGPoint) {
        frame.origin = origin
        positionSetCount += 1
    }

    func setSize(_ size: CGSize) {
        frame.size = size
        sizeSetCount += 1
    }

    func focus() { focusCount += 1 }

    func moveTo(_ frame: CGRect) {
        self.frame = frame
    }
}
