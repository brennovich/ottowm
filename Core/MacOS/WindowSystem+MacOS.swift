import CoreGraphics
import Foundation

extension WindowSystem {
    static func system(windowEvents: AXWindowEvents, applications: Applications) -> WindowSystem {
        WindowSystem(
            focusedWindow: OperationCache(windowEvents.adoptFocusedWindow),
            onScreenWindows: OperationCache { onScreenWindowFrames() },
            window: applications.findWindow(by:)
        )
    }
}

/// `level` keeps only the windows at that window level.
func onScreenWindowFrames(level: Int? = nil) -> [CGWindowID: CGRect] {
    let onScreen = trace(.read, "CGWindowList") {
        CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []
    }

    return onScreen.reduce(into: [CGWindowID: CGRect]()) { frames, info in
        guard level == nil || info[kCGWindowLayer as String] as? Int == level,
              let number = info[kCGWindowNumber as String] as? NSNumber,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds)
        else { return }

        frames[CGWindowID(number.uint32Value)] = frame
    }
}

/// The description leaves out `kCGWindowIsOnscreen` for a window that is not on screen.
func isWindowOnScreen(_ windowId: CGWindowID) -> Bool {
    var pointer = UnsafeRawPointer(bitPattern: UInt(windowId))
    let description = trace(.read, "CGWindowDescription") {
        CFArrayCreate(nil, &pointer, 1, nil).flatMap { CGWindowListCreateDescriptionFromArray($0) as? [[String: Any]] }
    }
    return description?.first?[kCGWindowIsOnscreen as String] as? Bool ?? false
}
