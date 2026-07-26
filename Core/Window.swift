import CoreGraphics

// A OttoWM window.
protocol Window: AnyObject {
    var id: CGWindowID { get }
    var appName: String { get }
    var isStandard: Bool { get }
    var isFullScreen: Bool { get }
    var isMinimized: Bool { get }
    var tabCount: Int { get }
    var frame: CGRect { get set }
    var tabInferenceYTolerance: CGFloat { get }

    func focus()
    func isTab(of other: any Window) -> Bool
}

extension Window {
    var tabInferenceYTolerance: CGFloat { 10 }

    // As macOS does not tell us whether two windows are tabs of the same
    // application, infers with some heuristics.
    func isTab(of other: any Window) -> Bool {
        tabCount > 1
            && appName == other.appName
            && frame.origin.x == other.frame.origin.x
            && abs(frame.origin.y - other.frame.origin.y) <= tabInferenceYTolerance
            && frame.width == other.frame.width
            && frame.height == other.frame.height
    }
}
