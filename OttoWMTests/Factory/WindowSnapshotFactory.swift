import CoreGraphics

func makeSnapshot(
    _ id: CGWindowID,
    appName: String = "App",
    frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
    tabCount: Int = 1,
    isStandard: Bool = true,
    isFullScreen: Bool = false,
    isMinimized: Bool = false
) -> WindowSnapshot {
    StubWindow(
        id: id,
        appName: appName,
        frame: frame,
        tabCount: tabCount,
        isStandard: isStandard,
        isFullScreen: isFullScreen,
        isMinimized: isMinimized
    ).snapshot()
}
