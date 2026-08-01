import AppKit
import CoreGraphics

enum WindowEvent {
    case created(WindowSnapshot)
    case focused(WindowSnapshot)
    case destroyed(CGWindowID)
    case minimized(CGWindowID)
    case unminimized(WindowSnapshot)
}
