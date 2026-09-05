import CoreGraphics

final class StubDesktop: Desktop {
    private let window: (CGWindowID) -> (any Window)?

    private(set) var placeCalls: [(windowId: CGWindowID, placement: Placement)] = []
    private(set) var placeBatches: [[CGWindowID]] = []
    private(set) var reframeCalls: [(windowId: CGWindowID, change: FrameChange)] = []
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

    /// Records the request only: every frame the change resolves to needs the screen bounds,
    /// which the real desktop owns.
    @discardableResult
    func reframe(_ windowId: CGWindowID, _ change: FrameChange) -> Bool {
        guard window(windowId) != nil else { return false }

        reframeCalls.append((windowId: windowId, change: change))
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
