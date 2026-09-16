import CoreGraphics
import Foundation
import SwiftUI

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

    /// The rotation of the top left mask that fits this corner.
    var rotation: Angle {
        switch self {
        case .topLeft: return .degrees(0)
        case .topRight: return .degrees(90)
        case .bottomLeft: return .degrees(270)
        }
    }
}
