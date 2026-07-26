import CoreGraphics

// The screen geometry the VirtualSpace strategy needs: full bounds for the
// hidden corner and visible bounds for recovery, both in top-left (AX) origin.
protocol Screen {
    var fullFrame: CGRect { get }
    var visibleFrame: CGRect { get }
}
