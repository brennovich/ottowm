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
    static let tabInferenceYTolerance: CGFloat = 10

    var logDescription: String { "id=\(id) app=\(appName)" }

    // As macOS does not tell us whether two windows are tabs of the same
    // application, infers with some heuristics.
    func isTab(of other: WindowSnapshot) -> Bool {
        tabCount > 1
            && appName == other.appName
            && frame.origin.x == other.frame.origin.x
            && abs(frame.origin.y - other.frame.origin.y) <= Self.tabInferenceYTolerance
            && frame.width == other.frame.width
            && frame.height == other.frame.height
    }
}
