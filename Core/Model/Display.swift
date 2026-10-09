import CoreGraphics

struct DisplayID: Hashable, Codable {
    let rawValue: String
}

enum ParkingCorner: String, Codable {
    case bottomRight, bottomLeft
}

struct Display: Equatable, Codable {
    let id: DisplayID
    let fullFrame: CGRect
    let visibleFrame: CGRect
    var parkingCorner = ParkingCorner.bottomRight
}

extension Display {
    /// What the desktop holds when AppKit reports no screen.
    static let unknown = Display(id: DisplayID(rawValue: "unknown"), fullFrame: .zero, visibleFrame: .zero)

    var logDescription: String { "\(id.rawValue) \(fullFrame) visible \(visibleFrame)" }
}

/// One display before and after a screen change, or a removed display and the one that takes
/// its windows.
struct DisplayChange: Equatable {
    let from: Display
    let to: Display

    var fit: Fit { Fit(from: from.visibleFrame, into: to.visibleFrame) }
}
