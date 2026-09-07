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
            .filter { candidate in
                switch direction {
                case .north: return candidate.value.midY < reference.midY
                case .south: return candidate.value.midY > reference.midY
                case .west: return candidate.value.midX < reference.midX
                case .east: return candidate.value.midX > reference.midX
                }
            }
            .min { rank($0, to: direction) < rank($1, to: direction) }?
            .key
    }

    private func rank(
        _ candidate: (key: CGWindowID, value: CGRect),
        to direction: Direction
    ) -> (Int, CGFloat, CGFloat, CGWindowID) {
        let center = CGPoint(x: candidate.value.midX, y: candidate.value.midY)
        let travelled = direction.isVertical ? abs(center.y - reference.midY) : abs(center.x - reference.midX)
        let across = direction.isVertical ? abs(center.x - reference.midX) : abs(center.y - reference.midY)

        return (sharesLane(candidate.value, to: direction) ? 0 : 1, travelled, across, candidate.key)
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
