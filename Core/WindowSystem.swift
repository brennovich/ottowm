import CoreGraphics
import Foundation

final class WindowSystem {
    private let focusedWindow: OperationCache<WindowSnapshot?>
    private let onScreenWindows: OperationCache<[CGWindowID: CGRect]>
    private let window: (CGWindowID) -> (any Window)?
    private let roundTrips: RoundTrips

    init(
        focusedWindow: OperationCache<WindowSnapshot?>,
        onScreenWindows: OperationCache<[CGWindowID: CGRect]>,
        window: @escaping (CGWindowID) -> (any Window)?,
        roundTrips: RoundTrips = .shared
    ) {
        self.focusedWindow = focusedWindow
        self.onScreenWindows = onScreenWindows
        self.window = window
        self.roundTrips = roundTrips
    }

    func duringOperation<T>(_ name: StaticString, _ body: () -> T) -> T {
        roundTrips.duringOperation(name) {
            onScreenWindows.duringOperation { focusedWindow.duringOperation(body) }
        }
    }

    func focused() -> WindowSnapshot? {
        focusedWindow.value()
    }

    func shows(_ windowId: CGWindowID) -> Bool {
        onScreenWindows.value().keys.contains(windowId)
    }

    func showsAny(_ windowIds: Set<CGWindowID>) -> Bool {
        !windowIds.isDisjoint(with: onScreenWindows.value().keys)
    }

    func frames(of windowIds: [CGWindowID]) -> [CGWindowID: CGRect] {
        let onScreen = onScreenWindows.value()
        return windowIds.reduce(into: [:]) { frames, windowId in
            frames[windowId] = onScreen[windowId]
        }
    }

    func snapshot(of windowId: CGWindowID) -> WindowSnapshot? {
        window(windowId)?.snapshot()
    }

    func tabCount(of windowId: CGWindowID) -> Int {
        window(windowId)?.tabCount() ?? 1
    }
}

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
