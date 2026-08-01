import CoreGraphics

protocol Window: AnyObject {
    func snapshot() -> WindowSnapshot
    func movableFrame() -> CGRect?
    func setFrame(_ frame: CGRect)
    func focus()
}
