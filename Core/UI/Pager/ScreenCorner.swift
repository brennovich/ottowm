import CoreGraphics
import Foundation

/// The screen corners that get a rounded mask. The bottom right corner is under the pager tab.
enum ScreenCorner: CaseIterable {
    case topLeft, topRight, bottomLeft

    /// Matches the window corner radius of the macOS version.
    static func radius(on version: OperatingSystemVersion) -> CGFloat {
        version.majorVersion >= 26 ? 16 : 9
    }

    /// `screenFrame` is in AppKit coordinates.
    func frame(in screenFrame: CGRect, radius: CGFloat) -> CGRect {
        let size = CGSize(width: radius, height: radius)
        switch self {
        case .topLeft: return CGRect(origin: CGPoint(x: screenFrame.minX, y: screenFrame.maxY - radius), size: size)
        case .topRight: return CGRect(origin: CGPoint(x: screenFrame.maxX - radius, y: screenFrame.maxY - radius), size: size)
        case .bottomLeft: return CGRect(origin: CGPoint(x: screenFrame.minX, y: screenFrame.minY), size: size)
        }
    }

    /// The mask of a square of side `radius`, in top left coordinates: the part of the square outside the
    /// quarter circle centered on its bottom right point, turned to fit this corner.
    func mask(radius: CGFloat) -> CGPath {
        let turn = CGAffineTransform(translationX: radius / 2, y: radius / 2)
            .rotated(by: rotation)
            .translatedBy(x: -radius / 2, y: -radius / 2)
        let path = CGMutablePath()
        path.move(to: .zero, transform: turn)
        path.addLine(to: CGPoint(x: 0, y: radius), transform: turn)
        path.addRelativeArc(center: CGPoint(x: radius, y: radius), radius: radius, startAngle: .pi, delta: .pi / 2, transform: turn)
        path.closeSubpath()
        return path
    }

    /// Where the mask moves to leave its square past the screen corner, in top left coordinates.
    func hiddenOffset(radius: CGFloat) -> CGSize {
        switch self {
        case .topLeft: return CGSize(width: -radius, height: -radius)
        case .topRight: return CGSize(width: radius, height: -radius)
        case .bottomLeft: return CGSize(width: -radius, height: radius)
        }
    }

    /// The rotation of the top left mask that fits this corner, in radians.
    private var rotation: CGFloat {
        switch self {
        case .topLeft: return 0
        case .topRight: return .pi / 2
        case .bottomLeft: return .pi * 3 / 2
        }
    }
}
