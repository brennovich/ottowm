import CoreGraphics

/// The windows around one reference frame, and which of them a focus move lands on.
struct Neighbors {
    private let reference: CGRect
    private let candidates: [CGWindowID: CGRect]

    init(around reference: CGRect, among candidates: [CGWindowID: CGRect]) {
        self.reference = reference
        self.candidates = candidates
    }

    /// The window `direction` leads to, or `nil` when no window lies that way.
    ///
    /// A window lies in the direction when its center does, so one covered by the reference, or
    /// behind it, is reachable like any other. A window sharing rows with the reference (columns,
    /// going north or south) wins over one that does not, however much closer that one is.
    func nearest(to direction: Direction) -> CGWindowID? {
        candidates
            .filter { lies($0.value, to: direction) }
            .min { rank($0, to: direction) < rank($1, to: direction) }?
            .key
    }

    private func lies(_ candidate: CGRect, to direction: Direction) -> Bool {
        switch direction {
        case .north: return candidate.midY < reference.midY
        case .south: return candidate.midY > reference.midY
        case .west: return candidate.midX < reference.midX
        case .east: return candidate.midX > reference.midX
        }
    }

    /// The candidate's sort key, where lower is nearer. Every distance is between the candidate's
    /// center and the reference's.
    ///
    /// - Returns: `(lane, travelled, across, id)`, compared in that order:
    ///   - `lane`: 0 when the candidate shares the lane with the reference, 1 when it does not,
    ///     so a window in the lane beats one out of it however much closer that one is.
    ///   - `travelled`: the distance along the axis the move travels.
    ///   - `across`: the distance on the axis it does not.
    ///   - `id`: the window id, so the same layout always leads to the same window.
    private func rank(
        _ candidate: (key: CGWindowID, value: CGRect),
        to direction: Direction
    ) -> (Int, CGFloat, CGFloat, CGWindowID) {
        let center = CGPoint(x: candidate.value.midX, y: candidate.value.midY)
        let travelled = direction.isVertical ? abs(center.y - reference.midY) : abs(center.x - reference.midX)
        let across = direction.isVertical ? abs(center.x - reference.midX) : abs(center.y - reference.midY)

        return (sharesLane(candidate.value, to: direction) ? 0 : 1, travelled, across, candidate.key)
    }

    /// Whether the two frames overlap on the axis the move does not travel.
    private func sharesLane(_ candidate: CGRect, to direction: Direction) -> Bool {
        direction.isVertical
            ? candidate.minX < reference.maxX && candidate.maxX > reference.minX
            : candidate.minY < reference.maxY && candidate.maxY > reference.minY
    }
}
