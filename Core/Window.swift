import CoreGraphics
import Foundation

protocol Window: AnyObject {
    /// The application the window belongs to. Calls to one application queue behind each
    /// other, calls to different ones do not.
    var pid: pid_t { get }

    func snapshot() -> WindowSnapshot
    func tabCount() -> Int
    func movableFrame() -> CGRect?
    func withoutAnimations(_ body: () -> Void)
    func setPosition(_ origin: CGPoint)
    func setSize(_ size: CGSize)
    func focus()
}
