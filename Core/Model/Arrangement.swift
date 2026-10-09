import CoreGraphics

/// The connected displays, the primary one first.
struct Arrangement {
    let displays: [Display]

    init(displays: [Display]) {
        self.displays = displays.map { display in
            var display = display
            display.parkingCorner = Self.parkingCorner(of: display, among: displays)
            return display
        }
    }

    /// The display holding the larger part of the frame, the rule macOS uses to give a window a
    /// Space. A parked window keeps a 1pt sliver on its display and overlaps no other display,
    /// unless displays cover the area beyond both bottom corners. Its centre can be nearer
    /// another display. The nearest display is taken only for a frame on no display.
    func display(of frame: CGRect) -> Display? {
        let overlaps = displays.map { (display: $0, area: area($0.fullFrame.intersection(frame))) }
        if let largest = overlaps.max(by: { $0.area < $1.area }), largest.area > 0 { return largest.display }

        return displays.min { distance($0.fullFrame, frame) < distance($1.fullFrame, frame) }
    }

    /// A parked window extends right and down from the bottom right corner, or left and down from
    /// the bottom left corner. macOS moves a window back only when its title bar is on no display,
    /// so a neighbour covering that area shows the window. The bottom right corner is kept when
    /// neighbours cover both areas.
    private static func parkingCorner(of display: Display, among displays: [Display]) -> ParkingCorner {
        let frame = display.fullFrame
        let below = displays.filter { $0.id != display.id && $0.fullFrame.maxY > frame.maxY - 1 }.map(\.fullFrame)
        let coversBottomRight = below.contains { $0.maxX > frame.maxX - 1 }
        let coversBottomLeft = below.contains { $0.minX < frame.minX + 1 }
        return coversBottomRight && !coversBottomLeft ? .bottomLeft : .bottomRight
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
