import CoreGraphics

protocol WindowLogDescribing {
    var id: CGWindowID { get }
    var appName: String { get }
}

extension WindowLogDescribing {
    var logDescription: String { "id=\(id) app=\(appName)" }
}

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
    var isAdmissible: Bool {
        id != 0 && !isFullScreen && !isMinimized && (isStandard || (hasCloseButton && hasMinimizeButton))
    }

    func moved(to frame: CGRect) -> WindowSnapshot {
        var moved = self
        moved.frame = frame
        return moved
    }
}
