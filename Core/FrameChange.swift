import CoreGraphics

enum FrameChange: Equatable {
    case step(Step)
    case center
    case park
    case unpark(CGRect?)
    case maximize(restoring: CGRect?)

    var logDescription: String {
        switch self {
        case let .step(step): "move \(step.direction.rawValue) by \(step.points)"
        case .center: "center"
        case .park: "park"
        case .unpark: "unpark"
        case let .maximize(restoring): restoring == nil ? "maximize" : "restore from maximize"
        }
    }
}

enum FrameOutcome: Hashable {
    case parked(CGWindowID, from: CGRect)
    case maximized(CGWindowID, from: CGRect)
    case active(CGWindowID)
    case gone(CGWindowID)
}
