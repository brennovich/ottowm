import CoreGraphics

// Represents a window on the screen.
struct Window {
    // Tolerance for inferring that two windows are tabs of the same application.
    static let tabInferrenceYTolerance: CGFloat = 10

    let id: CGWindowID
    let tabCount: Int
    let frame: CGRect
    let appName: String

    // Returns true if the other window is likely a tab of the same application.
    //
    // macOS does not provide a way to determine if two windows are tabs of the same
    // application, so we infer it with some heuristics.
    func isTab(of other: Window) -> Bool {
        tabCount > 1
            && appName == other.appName
            && frame.origin.x == other.frame.origin.x
            && abs(frame.origin.y - other.frame.origin.y) <= Self.tabInferrenceYTolerance
            && frame.width == other.frame.width
            && frame.height == other.frame.height
    }
}
