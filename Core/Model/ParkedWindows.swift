import CoreGraphics

final class ParkedWindows {
    private var parked: [CGWindowID: CGRect] = [:]

    var all: [CGWindowID: CGRect] {
        parked
    }

    func isParked(_ windowId: CGWindowID) -> Bool {
        parked[windowId] != nil
    }

    func parkedFrom(of windowId: CGWindowID) -> CGRect? {
        parked[windowId]
    }

    func record(_ outcomes: [FrameOutcome]) {
        for outcome in outcomes {
            switch outcome {
            case let .parked(windowId, parkedFrom): park(windowId, from: parkedFrom)
            case let .active(windowId): forget(windowId)
            case .filled, .gone: continue
            }
        }
    }

    func park(_ windowId: CGWindowID, from frame: CGRect) {
        parked[windowId] = frame
    }

    func park(_ frames: [CGWindowID: CGRect]) {
        parked.merge(frames) { _, new in new }
    }

    func forget(_ windowId: CGWindowID) {
        parked[windowId] = nil
    }
}
