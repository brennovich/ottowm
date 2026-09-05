import CoreGraphics

/// The frame each maximized window is to go back to. Recording the frame the window came
/// from, rather than the one it was given, keeps the original through a second maximize at
/// another inset.
final class MaximizedWindows {
    private var maximized: [CGWindowID: CGRect] = [:]

    func restoringFrame(of windowId: CGWindowID) -> CGRect? {
        maximized[windowId]
    }

    func record(_ outcomes: [FrameOutcome]) {
        for outcome in outcomes {
            switch outcome {
            case let .maximized(windowId, from): maximized[windowId] = maximized[windowId] ?? from
            case let .active(windowId): forget(windowId)
            case .parked, .gone: continue
            }
        }
    }

    func forget(_ windowId: CGWindowID) {
        maximized[windowId] = nil
    }
}
