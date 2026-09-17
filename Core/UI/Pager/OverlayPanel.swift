import AppKit

/// A borderless click-through panel holding one sliding view. It is ordered in while the view is revealed or sliding out.
final class OverlayPanel: NSPanel {
    private let content: SlidingView

    init(level: NSWindow.Level, content: SlidingView) {
        self.content = content
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = level
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        // A click on the panel reaches the window under it.
        ignoresMouseEvents = true
        // A panel hides when its application deactivates, and OttoWM is inactive except while an alert shows.
        hidesOnDeactivate = false
        // Without `.canJoinAllSpaces` the panel stays on the native Space it is shown on.
        collectionBehavior = [.stationary, .ignoresCycle]
        contentView = content
    }

    func reveal() {
        orderFrontRegardless()
        content.reveal()
    }

    /// `done` runs once the content has slid out, or when a reveal interrupts the slide.
    func conceal(then done: @escaping () -> Void) {
        content.conceal { [weak self] in
            if let self, !self.content.isRevealed {
                self.orderOut(nil)
            }
            done()
        }
    }
}
