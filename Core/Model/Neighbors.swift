import CoreGraphics

struct Neighbors {
    private let reference: CGRect
    private let candidates: [CGWindowID: CGRect]

    init(around reference: CGRect, among candidates: [CGWindowID: CGRect]) {
        self.reference = reference
        self.candidates = candidates
    }

    func nearest(to direction: Direction) -> CGWindowID? {
        candidates
            .filter { lies($0.value, to: direction) || sharesCenter($0.value) }
            .min { rank($0, to: direction) < rank($1, to: direction) }?
            .key
    }

    /// Distance is measured between facing edges, not centers, so windows stacked in one column
    /// tie whatever their widths. The tie goes to the topmost window, or the leftmost one when
    /// moving vertically.
    private func rank(
        _ candidate: (key: CGWindowID, value: CGRect),
        to direction: Direction
    ) -> (Int, CGFloat, CGFloat, CGWindowID) {
        let frame = candidate.value
        let across = direction.isVertical ? frame.minX : frame.minY

        return (tier(frame, to: direction), gap(to: frame, direction), across, candidate.key)
    }

    private func gap(to candidate: CGRect, _ direction: Direction) -> CGFloat {
        switch direction {
        case .north: return reference.minY - candidate.maxY
        case .south: return candidate.minY - reference.maxY
        case .west: return reference.minX - candidate.maxX
        case .east: return candidate.minX - reference.maxX
        }
    }

    private func lies(_ candidate: CGRect, to direction: Direction) -> Bool {
        switch direction {
        case .north: return candidate.midY < reference.midY
        case .south: return candidate.midY > reference.midY
        case .west: return candidate.midX < reference.midX
        case .east: return candidate.midX > reference.midX
        }
    }

    private func sharesCenter(_ candidate: CGRect) -> Bool {
        candidate.midX == reference.midX && candidate.midY == reference.midY
    }

    /// A window sharing the reference center lies in no direction, so it is taken in every one,
    /// behind any window that does lie that way. Two centered windows are otherwise unreachable
    /// from each other.
    private func tier(_ candidate: CGRect, to direction: Direction) -> Int {
        guard lies(candidate, to: direction) else { return 2 }

        return sharesLane(candidate, to: direction) ? 0 : 1
    }

    /// A window that only overlaps the reference by an edge is not in its lane: one wide
    /// enough to reach into the next column would rank ahead of the window directly below it
    /// on a few points of distance. Two windows share a lane when either center falls within
    /// the span of the other.
    private func sharesLane(_ candidate: CGRect, to direction: Direction) -> Bool {
        if direction.isVertical {
            return (candidate.midX >= reference.minX && candidate.midX <= reference.maxX)
                || (reference.midX >= candidate.minX && reference.midX <= candidate.maxX)
        }

        return (candidate.midY >= reference.minY && candidate.midY <= reference.maxY)
            || (reference.midY >= candidate.minY && reference.midY <= candidate.maxY)
    }
}
