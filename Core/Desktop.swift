import CoreGraphics

protocol Desktop {
    func recover(_ windows: [WindowSnapshot]) -> [WindowSnapshot]
    func reframe(_ changes: [(windowId: CGWindowID, change: FrameChange)]) -> [FrameOutcome]
    func focus(_ windowId: CGWindowID) -> Bool
    func startWatching(nativeSpaceChange callback: @escaping () -> Void)
    func repark(_ parked: [(windowId: CGWindowID, parkedFrom: CGRect)])
}
