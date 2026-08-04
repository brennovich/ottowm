import CoreGraphics

final class StubDesktop: Desktop {
    private let window: (CGWindowID) -> (any Window)?

    private(set) var placements: [CGWindowID: Placement] = [:]
    private(set) var placeCalls: [(windowId: CGWindowID, placement: Placement)] = []
    private(set) var forgottenWindowIds: [CGWindowID] = []
    private(set) var recoverCount = 0
    private(set) var recoveredWindowIds: [CGWindowID] = []
    private(set) var manualNavigationCallback: ((CGWindowID) -> Void)?

    var recoveredFrames: [CGWindowID: CGRect] = [:]

    init(window: @escaping (CGWindowID) -> (any Window)? = { _ in nil }) {
        self.window = window
    }

    func recover(windows: [WindowSnapshot]) -> [WindowSnapshot] {
        recoverCount += 1
        recoveredWindowIds = windows.map(\.id)
        return windows.map { win in
            recoveredFrames[win.id].map { win.moved(to: $0) } ?? win
        }
    }

    func place(_ windowId: CGWindowID, _ placement: Placement) {
        placeCalls.append((windowId: windowId, placement: placement))
        placements[windowId] = placement
    }

    func placement(of windowId: CGWindowID) -> Placement {
        placements[windowId] ?? .active
    }

    func focus(_ windowId: CGWindowID) -> Bool {
        guard let win = window(windowId) else { return false }
        win.focus()
        return true
    }

    func startWatchingForManualNavigation(_ callback: @escaping (CGWindowID) -> Void) {
        manualNavigationCallback = callback
    }

    func forget(_ windowId: CGWindowID) {
        forgottenWindowIds.append(windowId)
        placements[windowId] = nil
    }
}
