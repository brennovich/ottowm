import CoreGraphics

/// The size of the pager tab and the frame of its badge, taken from the Hammerspoon Pager spoon.
enum PagerTab {
    static let size = CGSize(width: 54, height: 58)
    static let badge = CGRect(x: 28, y: 27.25, width: 20, height: 21)

    /// `screenFrame` is in AppKit coordinates. The bottom right corner is where `HiddenEdge` parks windows.
    static func frame(in screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.maxX - size.width, y: screenFrame.minY, width: size.width, height: size.height)
    }
}
