import CoreGraphics

final class StubSpace: Space {
    var isOnManagedSpaceValue = true
    var unmanagedWindowIds: Set<CGWindowID> = []

    private(set) var placements: [CGWindowID: Placement] = [:]
    private(set) var movedCalls: [(windowId: CGWindowID, placement: Placement)] = []
    private(set) var forgottenWindowIds: [CGWindowID] = []
    private(set) var setupForMainScreenCount = 0
    private(set) var activateManagedSpaceCount = 0
    private(set) var manualNavigationCallback: ((Placement) -> Void)?

    func setupForMainScreen() {
        setupForMainScreenCount += 1
    }

    func isOnManagedSpace() -> Bool {
        isOnManagedSpaceValue
    }

    func activateManagedSpace() {
        activateManagedSpaceCount += 1
    }

    func managesWindow(_ windowId: CGWindowID) -> Bool {
        !unmanagedWindowIds.contains(windowId)
    }

    func moveWindowToSpace(_ windowId: CGWindowID, _ space: Placement) {
        movedCalls.append((windowId: windowId, placement: space))
        placements[windowId] = space
    }

    func windowSpaces(_ windowId: CGWindowID) -> Placement {
        placements[windowId] ?? .active
    }

    func startWatchingForManualNavigation(_ callback: @escaping (Placement) -> Void) {
        manualNavigationCallback = callback
    }

    func forgetWindow(_ windowId: CGWindowID) {
        forgottenWindowIds.append(windowId)
        placements[windowId] = nil
    }
}
