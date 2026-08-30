import CoreGraphics

/// `Desktop` moves and focuses windows in the one native macOS Space.
protocol Desktop {
    func recover(_ windows: [WindowSnapshot]) -> [WindowSnapshot]
    /// Places every window of the batch, in the order given. `owedFrame` is the frame a
    /// window already parked is owed back, and `nil` for one on screen.
    /// - Returns: what each placement leaves for the model to record, in no particular
    ///   order. A window already parked is left where it is, and reported as such.
    func place(_ placements: [(windowId: CGWindowID, placement: Placement, owedFrame: CGRect?)]) -> [PlacementOutcome]
    /// Moves the window one step, keeping it on screen.
    /// - Returns: `false` if the window no longer exists, so the caller can drop it.
    @discardableResult
    func move(_ windowId: CGWindowID, _ step: Step) -> Bool
    func focus(_ windowId: CGWindowID) -> Bool
    /// Reports every change of the native Space in front.
    func startWatching(nativeSpaceChange callback: @escaping () -> Void)
    /// Moves back to the hidden edge the parked windows that are on screen, each to the
    /// frame it is owed. A window still at the edge is left alone.
    func repark(_ parked: [(windowId: CGWindowID, owedFrame: CGRect)])
}
