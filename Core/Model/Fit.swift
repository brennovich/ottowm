import CoreGraphics

/// Moves a frame from one visible frame into another: the size is kept when it fits, and each
/// axis keeps its share of the room left, so a centered window stays centered and one against
/// an edge stays against it.
struct Fit: Equatable {
    let from: CGRect
    let into: CGRect

    func frame(_ frame: CGRect) -> CGRect {
        let size = CGSize(width: min(frame.width, into.width), height: min(frame.height, into.height))

        return CGRect(
            x: into.minX + share(frame.minX - from.minX, of: from.width - frame.width) * (into.width - size.width),
            y: into.minY + share(frame.minY - from.minY, of: from.height - frame.height) * (into.height - size.height),
            width: size.width,
            height: size.height
        )
    }

    private func share(_ offset: CGFloat, of room: CGFloat) -> CGFloat {
        guard room > 0 else { return 0 }
        return min(max(offset / room, 0), 1)
    }
}
