import CoreGraphics

final class StubDesktop: Desktop {
    private let window: (CGWindowID) -> (any Window)?

    var display: Display = .standard

    private(set) var reframeCalls: [(windowId: CGWindowID, change: FrameChange)] = []
    private(set) var reframeBatches: [[CGWindowID]] = []
    private(set) var recoveredWindowIds: [CGWindowID] = []
    private(set) var reparkedWindowIds: [[CGWindowID]] = []
    private(set) var handler: ((DesktopEvent) -> Void)?

    var recoveredFrames: [CGWindowID: CGRect] = [:]

    init(window: @escaping (CGWindowID) -> (any Window)? = { _ in nil }) {
        self.window = window
    }

    /// Moves the window as the real desktop does, so what is read back afterwards is where
    /// the recovery put it.
    func recover(_ windows: [WindowSnapshot]) -> [WindowSnapshot] {
        recoveredWindowIds = windows.map(\.id)
        return windows.map { win in
            guard let recovered = recoveredFrames[win.id], let target = window(win.id) else { return win }

            target.withoutAnimations {
                target.setPosition(recovered.origin)
                target.setSize(recovered.size)
            }
            return win.moved(to: recovered)
        }
    }

    /// Records the request, and returns a frame for a park: every other frame a change
    /// resolves to needs the screen bounds, which the real desktop owns.
    func reframe(_ changes: [(windowId: CGWindowID, change: FrameChange)]) -> [FrameOutcome] {
        reframeBatches.append(changes.map(\.windowId))
        reframeCalls.append(contentsOf: changes)

        return changes.map { request in
            guard let win = window(request.windowId) else { return .gone(request.windowId) }

            switch request.change {
            case let .park(from: known): return .parked(request.windowId, from: known ?? win.snapshot().frame)
            case .unpark, .step, .resize, .center: return .active(request.windowId)
            case let .maximize(restoring), let .fill(_, restoring):
                guard restoring == nil else { return .active(request.windowId) }
                return .filled(request.windowId, from: win.snapshot().frame)
            }
        }
    }

    func clearCalls() {
        reframeCalls = []
        reframeBatches = []
    }

    func focus(_ windowId: CGWindowID) -> Bool {
        guard let win = window(windowId) else { return false }
        win.focus()
        return true
    }

    func startWatching(_ handler: @escaping (DesktopEvent) -> Void) {
        self.handler = handler
    }

    func repark(_ parked: [(windowId: CGWindowID, parkedFrom: CGRect)]) {
        reparkedWindowIds.append(parked.map(\.windowId))
    }
}
