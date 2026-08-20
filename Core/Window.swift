import CoreGraphics

protocol Window: AnyObject {
    func snapshot() -> WindowSnapshot
    func tabCount() -> Int
    func movableFrame() -> CGRect?
    func withoutAnimations(_ body: () -> Void)
    func setPosition(_ origin: CGPoint)
    func setSize(_ size: CGSize)
    func focus()
}
