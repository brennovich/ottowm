import CoreGraphics

/// The screen rect the pager tab covers, in top left coordinates, and whether a window reaches into it.
struct TabArea {
    let frame: CGRect
    private let display: Display
    private let hiddenEdge: HiddenEdge

    init(display: Display) {
        frame = display.fullFrame.bottomRight(size: TabShape.size)
        self.display = display
        hiddenEdge = HiddenEdge(display: display)
    }

    /// During a full screen transition macOS shows a window the size of the display at the normal level for about 500ms,
    /// on the Space where the tab is shown. A window that covers the whole display is not counted. A window zoomed to the
    /// whole display while the menu bar hides automatically is not counted either.
    func isOverlapped(by frames: [CGWindowID: CGRect]) -> Bool {
        frames.values.contains { window in
            !hiddenEdge.holds(window) && window.intersects(frame) && !window.contains(display.fullFrame)
        }
    }
}
