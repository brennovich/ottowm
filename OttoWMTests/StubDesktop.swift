import CoreGraphics

final class StubDesktop: Desktop {
    var isFrontmostValue = true
    var absentWindowIds: Set<CGWindowID> = []

    private(set) var placements: [CGWindowID: Placement] = [:]
    private(set) var placeCalls: [(windowId: CGWindowID, placement: Placement)] = []
    private(set) var forgottenWindowIds: [CGWindowID] = []
    private(set) var setupForMainScreenCount = 0
    private(set) var setupWindowIds: [CGWindowID] = []
    private(set) var bringToFrontCount = 0
    private(set) var manualNavigationCallback: ((CGWindowID) -> Void)?

    func setupForMainScreen(windows: [WindowSnapshot]) {
        setupForMainScreenCount += 1
        setupWindowIds = windows.map(\.id)
    }

    func isFrontmost() -> Bool {
        isFrontmostValue
    }

    func bringToFront() {
        bringToFrontCount += 1
    }

    func contains(_ windowId: CGWindowID) -> Bool {
        !absentWindowIds.contains(windowId)
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
