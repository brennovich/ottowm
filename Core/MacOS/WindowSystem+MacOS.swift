import CoreGraphics
import Foundation

extension WindowSystem {
    static func system(windowEvents: AXWindowEvents, applications: Applications) -> WindowSystem {
        WindowSystem(
            focusedWindow: OperationCache(windowEvents.adoptFocusedWindow),
            onScreenWindows: OperationCache {
                let onScreen = trace(.read, "CGWindowList") {
                    CGWindowListCopyWindowInfo(
                        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
                    ) as? [[String: Any]] ?? []
                }

                return onScreen.reduce(into: [CGWindowID: CGRect]()) { frames, info in
                    guard let number = info[kCGWindowNumber as String] as? NSNumber,
                          let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                          let frame = CGRect(dictionaryRepresentation: bounds)
                    else { return }

                    frames[CGWindowID(number.uint32Value)] = frame
                }
            },
            window: applications.findWindow(by:)
        )
    }
}
