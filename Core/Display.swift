import CoreGraphics

struct DisplayID: Hashable {
    let rawValue: String
}

struct Display: Equatable {
    let id: DisplayID
    let fullFrame: CGRect
    let visibleFrame: CGRect
}

extension Display {
    /// What the desktop holds when AppKit reports no screen.
    static let unknown = Display(id: DisplayID(rawValue: "unknown"), fullFrame: .zero, visibleFrame: .zero)

    var logDescription: String { "\(id.rawValue) \(fullFrame) visible \(visibleFrame)" }
}

/// The display left and the one entered. A change that keeps the display is the Dock, the menu
/// bar or the scaling moving: the id is the same, the visible frame is not.
struct DisplayChange: Equatable {
    let from: Display
    let to: Display

    var keepsDisplay: Bool { from.id == to.id }
    var fit: Fit { Fit(from: from.visibleFrame, into: to.visibleFrame) }
}
