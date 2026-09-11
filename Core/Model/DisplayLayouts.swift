import CoreGraphics

/// The last frame each window had on each display. The layout of a disconnected display is
/// kept, so its windows go back where they were when it returns.
final class DisplayLayouts {
    private var frames: [DisplayID: [CGWindowID: CGRect]] = [:]

    func frame(of windowId: CGWindowID, on display: DisplayID) -> CGRect? {
        frames[display]?[windowId]
    }

    func record(_ frame: CGRect, of windowId: CGWindowID, on display: DisplayID) {
        frames[display, default: [:]][windowId] = frame
    }

    func record(_ outcomes: [FrameOutcome], on display: DisplayID) {
        for case let .parked(windowId, from) in outcomes {
            record(from, of: windowId, on: display)
        }
    }

    func forget(_ windowId: CGWindowID) {
        for display in frames.keys {
            frames[display]?[windowId] = nil
        }
    }
}
