import CoreGraphics

enum FrameChange: Equatable {
    case step(Step)
    case center
    case park
    case unpark(CGRect?)
    case maximize(restoring: CGRect?)
    case fill(Direction, restoring: CGRect?)

    /// The suffix reports that a frame to restore is on record, not that the window will take
    /// it: the desktop restores only when the window already fills the target.
    var logDescription: String {
        switch self {
        case let .step(step): "move \(step.direction.rawValue) by \(step.points)"
        case .center: "center"
        case .park: "park"
        case .unpark: "unpark"
        case let .maximize(restoring): "maximize\(Self.suffix(restoring))"
        case let .fill(direction, restoring): "fill \(direction.rawValue)\(Self.suffix(restoring))"
        }
    }

    private static func suffix(_ restoring: CGRect?) -> String {
        restoring == nil ? "" : " with a frame to restore"
    }
}

enum FrameOutcome: Hashable {
    case parked(CGWindowID, from: CGRect)
    case filled(CGWindowID, from: CGRect)
    case active(CGWindowID)
    case gone(CGWindowID)
}
