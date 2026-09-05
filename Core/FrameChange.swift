enum FrameChange: Equatable {
    case step(Step)
    case center

    /// Kept apart so the round-trip cost of a step and of a centering stay separate operations.
    var operation: StaticString {
        switch self {
        case .step: "move-window"
        case .center: "center-window"
        }
    }

    var logDescription: String {
        switch self {
        case let .step(step): "move \(step.direction.rawValue) by \(step.points)"
        case .center: "center"
        }
    }
}
