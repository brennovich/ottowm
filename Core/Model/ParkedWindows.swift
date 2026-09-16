import CoreGraphics

struct ParkedWindow: Codable, Equatable {
    let windowId: CGWindowID
    let parkedFrom: CGRect
}

final class ParkedWindows {
    private var parked: [CGWindowID: CGRect] = [:]

    var all: [ParkedWindow] {
        parked.sorted { $0.key < $1.key }.map { ParkedWindow(windowId: $0.key, parkedFrom: $0.value) }
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

    func forget(_ windowId: CGWindowID) {
        parked[windowId] = nil
    }
}
