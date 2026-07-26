import CoreGraphics

// macOS clamps a window from leaving all screens: horizontally to a 1px sliver,
// vertically keeping ~38px of title bar. Pinning both axes to the bottom-right
// corner confines the leftover to a tiny ~1x38px nub.
let hiddenEdgeEpsilon: CGFloat = 1
let hiddenEdgeDetectionMargin: CGFloat = 10

func hiddenFrame(for windowFrame: CGRect, on screen: Screen) -> CGRect {
    CGRect(
        x: screen.fullFrame.maxX - hiddenEdgeEpsilon,
        y: screen.fullFrame.maxY - hiddenEdgeEpsilon,
        width: windowFrame.width,
        height: windowFrame.height
    )
}

func isStuckAtHiddenEdge(_ frame: CGRect, on screen: Screen) -> Bool {
    frame.minX >= screen.fullFrame.maxX - hiddenEdgeEpsilon - hiddenEdgeDetectionMargin
}

func recoveredFrame(for windowFrame: CGRect, visibleFrame: CGRect) -> CGRect {
    let width = min(windowFrame.width, visibleFrame.width)
    let height = min(windowFrame.height, visibleFrame.height)

    return CGRect(
        x: visibleFrame.minX + (visibleFrame.width - width) / 2,
        y: visibleFrame.minY + (visibleFrame.height - height) / 2,
        width: width,
        height: height
    )
}
