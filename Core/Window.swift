import CoreGraphics

// A handle on a live macOS window: one batched read of its state plus the two
// commands OttoWM issues. Everything else works on WindowSnapshot values.
protocol Window: AnyObject {
    func snapshot() -> WindowSnapshot

    // The frame to move the window from, or nil when it cannot be moved: it is
    // minimized, or its geometry no longer reads back.
    func movableFrame() -> CGRect?

    func setFrame(_ frame: CGRect)
    func focus()
}
