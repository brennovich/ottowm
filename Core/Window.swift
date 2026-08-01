import CoreGraphics

protocol Window: AnyObject {
    func snapshot() -> WindowSnapshot

    // The frame to move the window from, or nil when it cannot be moved: it is
    // minimized, or its geometry no longer reads back.
    func movableFrame() -> CGRect?

    func setFrame(_ frame: CGRect)
    func focus()
}
