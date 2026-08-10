import CoreGraphics

protocol Window: AnyObject {
    func snapshot() -> WindowSnapshot
    // Walks the window's accessibility children, so it is read only when a window is
    // admitted and its tab group has to be worked out — never as part of a snapshot.
    func tabCount() -> Int
    func movableFrame() -> CGRect?
    // Scopes the frame writes, which the owning application would otherwise animate.
    func withoutAnimations(_ body: () -> Void)
    func setPosition(_ origin: CGPoint)
    func setSize(_ size: CGSize)
    func focus()
}
