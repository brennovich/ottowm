import CoreGraphics

final class StubDesktop: Desktop {
    private let window: (CGWindowID) -> (any Window)?

    private(set) var reframeCalls: [(windowId: CGWindowID, change: FrameChange)] = []
    private(set) var reframeBatches: [[CGWindowID]] = []
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

    /// Records the request, and answers a park with a frame: every other frame a change
    /// resolves to needs the screen bounds, which the real desktop owns.
    func reframe(_ changes: [(windowId: CGWindowID, change: FrameChange)]) -> [FrameOutcome] {
        reframeBatches.append(changes.map(\.windowId))
        reframeCalls.append(contentsOf: changes)

        return changes.map { request in
            guard let win = window(request.windowId) else { return .gone(request.windowId) }

            switch request.change {
            case .park: return .parked(request.windowId, from: win.snapshot().frame)
            case .unpark, .step, .center: return .active(request.windowId)
            case let .maximize(restoring):
                guard restoring == nil else { return .active(request.windowId) }
                return .maximized(request.windowId, from: win.snapshot().frame)
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

    func startWatching(nativeSpaceChange callback: @escaping () -> Void) {
        nativeSpaceChangeCallback = callback
    }

    func repark(_: [(windowId: CGWindowID, parkedFrom: CGRect)]) {}
}
