import CoreGraphics

protocol Desktop {
    func recover(_ windows: [WindowSnapshot]) -> [WindowSnapshot]
    func place(_ placements: [(windowId: CGWindowID, placement: Placement, owedFrame: CGRect?)]) -> [PlacementOutcome]
    @discardableResult
    func reframe(_ windowId: CGWindowID, _ change: FrameChange) -> Bool
    func focus(_ windowId: CGWindowID) -> Bool
    func startWatching(nativeSpaceChange callback: @escaping () -> Void)
    func repark(_ parked: [(windowId: CGWindowID, owedFrame: CGRect)])
}
