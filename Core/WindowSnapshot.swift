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
    // A standard subrole is not the only real window: an application drawing its own
    // decorations reports AXDialog, as does a hidden application's, and Quick Look or an
    // image viewer reports AXFloatingWindow. The title bar buttons are what separate the
    // real windows from the popups.
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
