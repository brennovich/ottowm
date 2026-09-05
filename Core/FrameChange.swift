import CoreGraphics

enum FrameChange: Equatable {
    case step(Step)
    case center
    case park
    case unpark(CGRect?)

    var logDescription: String {
        switch self {
        case let .step(step): "move \(step.direction.rawValue) by \(step.points)"
        case .center: "center"
        case .park: "park"
        case .unpark: "unpark"
        }
    }
}

enum FrameOutcome: Hashable {
    case parked(CGWindowID, from: CGRect)
    case active(CGWindowID)
    case gone(CGWindowID)
}
