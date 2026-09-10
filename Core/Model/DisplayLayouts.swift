import CoreGraphics

/// The last frame each window had on each display. The layout of a disconnected display is
/// kept, so its windows go back where they were when it returns.
final class DisplayLayouts {
    private let display: () -> DisplayID

    private var frames: [DisplayID: [CGWindowID: CGRect]] = [:]

    init(display: @escaping () -> DisplayID) {
        self.display = display
    }

    func frame(of windowId: CGWindowID, on display: DisplayID) -> CGRect? {
        frames[display]?[windowId]
    }

    func record(_ frame: CGRect, of windowId: CGWindowID) {
        frames[display(), default: [:]][windowId] = frame
    }

    func record(_ outcomes: [FrameOutcome]) {
        for case let .parked(windowId, from) in outcomes {
            record(from, of: windowId)
        }
    }

    func forget(_ windowId: CGWindowID) {
        for display in frames.keys {
            frames[display]?[windowId] = nil
        }
    }
}
