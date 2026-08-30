import CoreGraphics

final class ParkedWindows {
    private var owedFrames: [CGWindowID: CGRect] = [:]

    var all: [(windowId: CGWindowID, owedFrame: CGRect)] {
        owedFrames.sorted { $0.key < $1.key }.map { (windowId: $0.key, owedFrame: $0.value) }
    }

    func placement(of windowId: CGWindowID) -> Placement {
        owedFrames[windowId] != nil ? .parked : .active
    }

    func owedFrame(of windowId: CGWindowID) -> CGRect? {
        owedFrames[windowId]
    }

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
