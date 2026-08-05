import CoreGraphics

protocol Window: AnyObject {
    func snapshot() -> WindowSnapshot
    func movableFrame() -> CGRect?
    func setPosition(_ origin: CGPoint)
    func setSize(_ size: CGSize)
    func focus()
}
