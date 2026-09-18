import CoreGraphics
import Foundation

protocol Window: AnyObject {
    var pid: pid_t { get }

    func snapshot() -> WindowSnapshot
    func tabCount() -> Int
    func movableFrame() -> CGRect?
    /// Suspends the frame animations of the application for `body`, which may write the
    /// frames of every window of that application.
    func withoutAnimations<T>(_ body: () -> T) -> T
    func setPosition(_ origin: CGPoint)
    func setSize(_ size: CGSize)
    func focus()
}
