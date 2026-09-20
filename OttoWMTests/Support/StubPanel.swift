import AppKit

/// Drives the view the way `OverlayPanel` does, without putting it on screen.
final class StubPanel: Panel {
    let windowNumber = 1

    private let content: SlidingView

    init(level: NSWindow.Level, content: SlidingView) {
        self.content = content
    }

    func setFrame(_ frame: CGRect, display: Bool) {}

    func reveal() {
        content.reveal()
    }

    func conceal(then done: @escaping () -> Void) {
        content.conceal(then: done)
    }
}
