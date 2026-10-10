import CoreGraphics

/// The connected displays, the primary one first.
struct Arrangement {
    let displays: [Display]

    /// The display holding the larger part of the frame, the rule macOS uses to give a window a
    /// Space. A parked window keeps a 1pt sliver on its display and overlaps no other display,
    /// unless a display covers the area beyond its bottom right corner. Its centre can be nearer
    /// another display. The nearest display is taken only for a frame on no display.
    func display(of frame: CGRect) -> Display? {
        let overlaps = displays.map { (display: $0, area: area($0.fullFrame.intersection(frame))) }
        if let largest = overlaps.max(by: { $0.area < $1.area }), largest.area > 0 { return largest.display }

        return displays.min { distance($0.fullFrame, frame) < distance($1.fullFrame, frame) }
    }

    private func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private func distance(_ rect: CGRect, _ other: CGRect) -> CGFloat {
        let dx = max(0, rect.minX - other.maxX, other.minX - rect.maxX)
        let dy = max(0, rect.minY - other.maxY, other.minY - rect.maxY)
        return hypot(dx, dy)
    }
}
