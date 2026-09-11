import CoreGraphics

enum FrameChange: Equatable {
    case step(Step)
    case resize(Resize)
    case center
    case park(from: CGRect?)
    case unpark(CGRect?)
    case maximize(restoring: CGRect?)
    case fill(Direction, restoring: CGRect?)

    var logDescription: String {
        switch self {
        case let .step(step): "move \(step.direction.rawValue) by \(step.points)"
        case let .resize(resize): "resize \(resize.change.rawValue) by \(resize.points)"
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

struct FrameRequest: Equatable {
    let windowId: CGWindowID
    let change: FrameChange
}

enum FrameOutcome: Hashable {
    case parked(CGWindowID, from: CGRect)
    case filled(CGWindowID, from: CGRect)
    case active(CGWindowID)
    case gone(CGWindowID)
}

extension [FrameOutcome] {
    var gone: [CGWindowID] {
        compactMap { outcome in
            guard case let .gone(windowId) = outcome else { return nil }
            return windowId
        }
    }
}
