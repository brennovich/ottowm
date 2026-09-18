import CoreGraphics

enum FrameChange: Equatable {
    case move(Direction)
    case resize(Resize.Change)
    case center
    case park(from: CGRect?)
    case unpark(CGRect?)
    case maximize(restoring: CGRect?)
    case tile(Direction, restoring: CGRect?)

    var logDescription: String {
        switch self {
        case let .move(direction): "move \(direction.rawValue)"
        case let .resize(change): "resize \(change.rawValue)"
        case .center: "center"
        case .park: "park"
        case .unpark: "unpark"
        case let .maximize(restoring): "maximize\(Self.suffix(restoring))"
        case let .tile(direction, restoring): "tile \(direction.rawValue)\(Self.suffix(restoring))"
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

extension FrameRequest {
    /// The outcome to record when the window's frame cannot be read: the frame the request carries is kept.
    var knownOutcome: FrameOutcome {
        switch change {
        case let .unpark(parkedFrom?), let .park(from: parkedFrom?): .parked(windowId, from: parkedFrom)
        case let .maximize(restoring?), let .tile(_, restoring?): .filled(windowId, from: restoring)
        case .move, .resize, .center, .park, .unpark, .maximize, .tile: .active(windowId)
        }
    }
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
