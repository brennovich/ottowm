import CoreGraphics

enum WindowEvent: Equatable {
    case created(WindowSnapshot)
    case focused(WindowSnapshot)
    case destroyed(CGWindowID)
    case minimized(CGWindowID)
    case unminimized(WindowSnapshot)
}
