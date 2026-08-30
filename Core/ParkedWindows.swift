import CoreGraphics

/// Model that holds the windows parked at the hidden edge, and the frame each one is owed
/// back when it returns to the screen.
final class ParkedWindows {
    private var owedFrames: [CGWindowID: CGRect] = [:]

    /// Every parked window and the frame it is owed, in window id order.
    var all: [(windowId: CGWindowID, owedFrame: CGRect)] {
        owedFrames.sorted { $0.key < $1.key }.map { (windowId: $0.key, owedFrame: $0.value) }
    }

    func placement(of windowId: CGWindowID) -> Placement {
        owedFrames[windowId] != nil ? .parked : .active
    }

    func owedFrame(of windowId: CGWindowID) -> CGRect? {
        owedFrames[windowId]
    }

    /// Takes what the `Desktop` reports about the windows it placed. A window that is gone
    /// keeps the frame it is owed, until it is dropped from the workspaces too.
    func record(_ outcomes: [PlacementOutcome]) {
        for outcome in outcomes {
            switch outcome {
            case let .parked(windowId, owedFrame): park(windowId, owing: owedFrame)
            case let .activated(windowId): forget(windowId)
            case .gone: continue
            }
        }
    }

    func park(_ windowId: CGWindowID, owing frame: CGRect) {
        owedFrames[windowId] = frame
    }

    func forget(_ windowId: CGWindowID) {
        owedFrames[windowId] = nil
    }
}
