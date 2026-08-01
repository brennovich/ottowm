import CoreGraphics

final class StubDesktop: Desktop {
    private(set) var placements: [CGWindowID: Placement] = [:]
    private(set) var placeCalls: [(windowId: CGWindowID, placement: Placement)] = []
    private(set) var forgottenWindowIds: [CGWindowID] = []
    private(set) var recoverCount = 0
    private(set) var recoveredWindowIds: [CGWindowID] = []
    private(set) var manualNavigationCallback: ((CGWindowID) -> Void)?

    func recover(windows: [WindowSnapshot]) {
        recoverCount += 1
        recoveredWindowIds = windows.map(\.id)
    }

    func place(_ windowId: CGWindowID, _ placement: Placement) {
        placeCalls.append((windowId: windowId, placement: placement))
        placements[windowId] = placement
    }

    func placement(of windowId: CGWindowID) -> Placement {
        placements[windowId] ?? .active
    }

    func startWatchingForManualNavigation(_ callback: @escaping (CGWindowID) -> Void) {
        manualNavigationCallback = callback
    }

    func forget(_ windowId: CGWindowID) {
        forgottenWindowIds.append(windowId)
        placements[windowId] = nil
    }
}
