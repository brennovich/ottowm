import CoreGraphics

// The swappable seam that performs the OS-touching part of a virtual-space operations. The pure
// Workspaces model manipulate windows without knowing the underlying Space implementation details.
protocol Space {
    func setupForMainScreen(windows: [any Window])
    func isOnManagedSpace() -> Bool
    func activateManagedSpace()
    func managesWindow(_ windowId: CGWindowID) -> Bool
    func moveWindowToSpace(_ windowId: CGWindowID, _ space: Placement)
    func windowSpaces(_ windowId: CGWindowID) -> Placement
    func startWatchingForManualNavigation(_ callback: @escaping (Placement) -> Void)
    func forgetWindow(_ windowId: CGWindowID)
}
