import AppKit

/// The window one pager view is shown in. `OverlayPanel` is the one the app runs with.
protocol Panel: AnyObject {
    var windowNumber: Int { get }

    func setFrame(_ frame: CGRect, display: Bool)
    func reveal()
    /// `done` runs once the content has slid out, or when a reveal interrupts the slide.
    func conceal(then done: @escaping () -> Void)
}

extension OverlayPanel: Panel {}
