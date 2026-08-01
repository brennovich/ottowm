import CoreGraphics

// A window's state at a point in time, read in one batched round trip. The pure
// model and the engine work on these values instead of live windows, so tab
// inference and workspace assignment cost no IPC at all.
struct WindowSnapshot: Sendable, Equatable {
    let id: CGWindowID
    let appName: String
    let isStandard: Bool
    let isFullScreen: Bool
    let isMinimized: Bool
    let tabCount: Int
    let frame: CGRect
}

extension WindowSnapshot {
    var logDescription: String { "id=\(id) app=\(appName)" }
}
