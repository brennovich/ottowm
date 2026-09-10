import CoreGraphics

enum DesktopEvent: Equatable {
    case nativeSpaceChange
    case displayChange(from: Display, to: Display)
    /// A screen parameters notification that keeps the display.
    case screenParametersChange
}

protocol Desktop {
    var display: Display { get }
    func recover(_ windows: [WindowSnapshot]) -> [WindowSnapshot]
    func reframe(_ changes: [(windowId: CGWindowID, change: FrameChange)]) -> [FrameOutcome]
    func focus(_ windowId: CGWindowID) -> Bool
    func startWatching(_ handler: @escaping (DesktopEvent) -> Void)
    func repark(_ parked: [(windowId: CGWindowID, parkedFrom: CGRect)])
}
