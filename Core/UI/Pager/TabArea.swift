import CoreGraphics

/// The screen rect the pager tab covers, in top left coordinates, and whether a window reaches into it.
struct TabArea {
    private let display: Display
    private let hiddenEdge: HiddenEdge

    init(display: Display) {
        self.display = display
        hiddenEdge = HiddenEdge(display: display)
    }

    var frame: CGRect { frame(of: TabShape.size) }

    /// The pager is drawn for the bottom right corner, and mirrored where the windows park in the bottom left.
    var isMirrored: Bool { display.parkingCorner == .bottomLeft }

    /// The rect of `size` in the parking corner of the display.
    func frame(of size: CGSize) -> CGRect {
        let x = isMirrored ? display.fullFrame.minX : display.fullFrame.maxX - size.width
        return CGRect(x: x, y: display.fullFrame.maxY - size.height, width: size.width, height: size.height)
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
