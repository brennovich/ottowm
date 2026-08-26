import CoreGraphics

/// The identity of a window in a log line.
protocol WindowLogDescribing {
    var id: CGWindowID { get }
    var appName: String { get }
}

extension WindowLogDescribing {
    var logDescription: String { "id=\(id) app=\(appName)" }
}

/// A window's state at one point in time. Read in a single batched round trip.
struct WindowSnapshot: Sendable, Equatable, WindowLogDescribing {
    let id: CGWindowID
    let appName: String
    let isStandard: Bool
    let hasCloseButton: Bool
    let hasMinimizeButton: Bool
    let isFullScreen: Bool
    let isMinimized: Bool
    var frame: CGRect
}

extension WindowSnapshot {
    /// A real window does not always carry the standard subrole: an application drawing
    /// its own decorations reports AXDialog, as does a hidden application's window, and
    /// Quick Look or an image viewer reports AXFloatingWindow. The title bar buttons
    /// separate real windows from popups.
    var isAdmissible: Bool {
        id != 0 && !isFullScreen && !isMinimized && (isStandard || (hasCloseButton && hasMinimizeButton))
    }

    func moved(to frame: CGRect) -> WindowSnapshot {
        var moved = self
        moved.frame = frame
        return moved
    }
}
