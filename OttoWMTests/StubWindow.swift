import CoreGraphics
import Foundation

final class StubWindow: Window {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let tabs: Int
    let isStandard: Bool
    let hasCloseButton: Bool
    let hasMinimizeButton: Bool
    var isFullScreen: Bool
    var isMinimized: Bool
    private(set) var frame: CGRect

    private(set) var snapshotReadCount = 0
    private(set) var positionSetCount = 0
    private(set) var sizeSetCount = 0
    private(set) var focusCount = 0
    private(set) var movableFrameCount = 0
    private(set) var tabCountReadCount = 0
    private(set) var animatedWriteCount = 0
    private(set) var positionSetThread: Thread?
    var onSetPosition: (() -> Void)?

    private var animationsDisabled = false

    init(
        id: CGWindowID,
        pid: pid_t = 0,
        appName: String = "App",
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
        tabCount: Int = 1,
        isStandard: Bool = true,
        hasCloseButton: Bool = true,
        hasMinimizeButton: Bool = true,
        isFullScreen: Bool = false,
        isMinimized: Bool = false
    ) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.frame = frame
        self.tabs = tabCount
        self.isStandard = isStandard
        self.hasCloseButton = hasCloseButton
        self.hasMinimizeButton = hasMinimizeButton
        self.isFullScreen = isFullScreen
        self.isMinimized = isMinimized
    }

    func snapshot() -> WindowSnapshot {
        snapshotReadCount += 1
        return WindowSnapshot(
            id: id,
            appName: appName,
            isStandard: isStandard,
            hasCloseButton: hasCloseButton,
            hasMinimizeButton: hasMinimizeButton,
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

    func withoutAnimations(_ body: () -> Void) {
        animationsDisabled = true
        body()
        animationsDisabled = false
    }

    func setPosition(_ origin: CGPoint) {
        onSetPosition?()
        frame.origin = origin
        positionSetCount += 1
        positionSetThread = Thread.current
        countAnimatedWrite()
    }

    func setSize(_ size: CGSize) {
        frame.size = size
        sizeSetCount += 1
        countAnimatedWrite()
    }

    func focus() { focusCount += 1 }

    func moveTo(_ frame: CGRect) {
        self.frame = frame
    }

    private func countAnimatedWrite() {
        if !animationsDisabled { animatedWriteCount += 1 }
    }
}
