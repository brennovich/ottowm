import CoreGraphics

// A window's state at a point in time, read in one batched round trip to reduce IPC calls.
struct WindowSnapshot: Sendable, Equatable {
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
    // A standard subrole is the plain case. It is not the only one: a window whose
    // application draws its own decorations reports AXDialog, as does a hidden
    // application's, and a Quick Look or an image viewer reports AXFloatingWindow. What
    // separates the real windows in that crowd from the popups is the title bar itself,
    // and what is left of it in the accessibility tree are the buttons.
    var isAdmissible: Bool {
        id != 0 && !isFullScreen && !isMinimized && (isStandard || (hasCloseButton && hasMinimizeButton))
    }

    var logDescription: String { "id=\(id) app=\(appName)" }

    func moved(to frame: CGRect) -> WindowSnapshot {
        var moved = self
        moved.frame = frame
        return moved
    }
}
