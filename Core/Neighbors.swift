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

        let sharesLane = direction.isVertical
            ? candidate.value.minX < reference.maxX && candidate.value.maxX > reference.minX
            : candidate.value.minY < reference.maxY && candidate.value.maxY > reference.minY

        return (sharesLane ? 0 : 1, travelled, across, candidate.key)
    }
}
