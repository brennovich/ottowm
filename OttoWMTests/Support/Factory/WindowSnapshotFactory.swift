import CoreGraphics

func makeSnapshot(
    _ id: CGWindowID,
    appName: String = "App",
    frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
    isStandard: Bool = true,
    hasCloseButton: Bool = true,
    hasMinimizeButton: Bool = true,
    isFullScreen: Bool = false,
    isMinimized: Bool = false
) -> WindowSnapshot {
    StubWindow(
        id: id,
        appName: appName,
        frame: frame,
        isStandard: isStandard,
        hasCloseButton: hasCloseButton,
        hasMinimizeButton: hasMinimizeButton,
        isFullScreen: isFullScreen,
        isMinimized: isMinimized
    ).snapshot()
}
