import CoreGraphics

protocol ScreenGeometry {
    var fullFrame: CGRect { get }
    var visibleFrame: CGRect { get }
}
