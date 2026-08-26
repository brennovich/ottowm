import CoreGraphics

/// `Desktop` moves and focuses windows in the one native macOS Space.
protocol Desktop {
    func recover(_ windows: [WindowSnapshot]) -> [WindowSnapshot]
    /// Places the window at `placement`.
    /// - Returns: `false` if the window no longer exists, so the caller can stop placing
    ///   it.
    @discardableResult
    func place(_ windowId: CGWindowID, at placement: Placement) -> Bool
    /// Moves every stored window back to its captured frame.
    func restoreAll()
    func placement(of windowId: CGWindowID) -> Placement
    func focus(_ windowId: CGWindowID) -> Bool
    func startWatching(manualNavigation callback: @escaping (CGWindowID) -> Void)
    func forget(_ windowId: CGWindowID)
}
