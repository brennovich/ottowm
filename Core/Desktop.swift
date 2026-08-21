import CoreGraphics

// The physical counterpart to the pure Workspaces model: where windows actually
// sit on screen, and the handle to the single native Space everything happens on.
protocol Desktop {
    func recover(windows: [WindowSnapshot]) -> [WindowSnapshot]
    // Reports whether the window still exists to be placed, so a caller holding a
    // gone one can stop asking.
    @discardableResult
    func place(_ windowId: CGWindowID, _ placement: Placement) -> Bool
    func placement(of windowId: CGWindowID) -> Placement
    func focus(_ windowId: CGWindowID) -> Bool
    func startWatchingForManualNavigation(_ callback: @escaping (CGWindowID) -> Void)
    func forget(_ windowId: CGWindowID)
}
