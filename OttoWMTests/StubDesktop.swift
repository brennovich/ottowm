import CoreGraphics

final class StubDesktop: Desktop {
    private let window: (CGWindowID) -> (any Window)?

    private(set) var placeCalls: [(windowId: CGWindowID, placement: Placement)] = []
    private(set) var placeBatches: [[CGWindowID]] = []
    private(set) var moveCalls: [(windowId: CGWindowID, step: Step)] = []
    private(set) var recoveredWindowIds: [CGWindowID] = []
    private(set) var nativeSpaceChangeCallback: (() -> Void)?

    var recoveredFrames: [CGWindowID: CGRect] = [:]

    init(window: @escaping (CGWindowID) -> (any Window)? = { _ in nil }) {
        self.window = window
    }

    func recover(_ windows: [WindowSnapshot]) -> [WindowSnapshot] {
        recoveredWindowIds = windows.map(\.id)
        return windows.map { win in
            recoveredFrames[win.id].map { win.moved(to: $0) } ?? win
        }
    }

    func place(_ placements: [(windowId: CGWindowID, placement: Placement, owedFrame: CGRect?)]) -> [PlacementOutcome] {
        placeBatches.append(placements.map(\.windowId))
        placeCalls.append(contentsOf: placements.map { (windowId: $0.windowId, placement: $0.placement) })

        return placements.map { request in
            guard let win = window(request.windowId) else { return .gone(request.windowId) }

            switch request.placement {
            case .parked:
                return .parked(request.windowId, owing: request.owedFrame ?? win.snapshot().frame)
            case .active:
                return .activated(request.windowId)
            }
        }
    }

    /// Applies the step without bounds, which is `Step`'s and the real desktop's job.
    @discardableResult
    func move(_ windowId: CGWindowID, _ step: Step) -> Bool {
        guard let win = window(windowId) else { return false }

        moveCalls.append((windowId: windowId, step: step))
        win.withoutAnimations {
            win.setPosition(step.frame(moving: win.snapshot().frame, within: .infinite).origin)
        }
        return true
    }

    func clearPlaceCalls() {
        placeCalls = []
        placeBatches = []
    }

    func focus(_ windowId: CGWindowID) -> Bool {
        guard let win = window(windowId) else { return false }
        win.focus()
        return true
    }

    func startWatching(nativeSpaceChange callback: @escaping () -> Void) {
        nativeSpaceChangeCallback = callback
    }

    func repark(_: [(windowId: CGWindowID, owedFrame: CGRect)]) {}
}
