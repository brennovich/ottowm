import CoreGraphics

/// Applies the `Workspaces` model to the screen: `Workspaces` records which workspace a
/// window belongs to, `Desktop` moves and focuses the windows to match. All workspaces
/// share one native macOS Space.
protocol Desktop {
    func recover(_ windows: [WindowSnapshot]) -> [WindowSnapshot]
    /// Places the window at `placement`.
    /// - Returns: `false` if the window no longer exists, so a caller holding a gone one
    ///   can stop asking.
    @discardableResult
    func place(_ windowId: CGWindowID, at placement: Placement) -> Bool
    /// Puts every stored window back at the frame it is owed, leaving the desk as it
    /// stood before OttoWM took it over.
    func restoreAll()
    func placement(of windowId: CGWindowID) -> Placement
    func focus(_ windowId: CGWindowID) -> Bool
    func startWatching(manualNavigation callback: @escaping (CGWindowID) -> Void)
    func forget(_ windowId: CGWindowID)
}
