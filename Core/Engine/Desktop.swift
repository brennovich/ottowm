import CoreGraphics

enum DesktopEvent: Equatable {
    case nativeSpaceChange
    case displayChange(DisplayChange)
    /// A screen parameters notification that keeps the display.
    case screenParametersChange
}

protocol Desktop {
    var display: Display { get }
    func recover(_ windows: [WindowSnapshot]) -> [WindowSnapshot]
    func reframe(_ requests: [FrameRequest]) -> [FrameOutcome]
    func isMaximized(_ frame: CGRect) -> Bool
    func focus(_ windowId: CGWindowID) -> Bool
    func startWatching(_ handler: @escaping (DesktopEvent) -> Void)
    func repark(_ windows: [CGWindowID: CGRect])
}
