import CoreGraphics

/// A consistent read of what the OS shows, optimized by caching system calls.
final class WindowSystem {
    private let focusedWindow: OperationCache<WindowSnapshot?>
    private let onScreenWindows: OperationCache<[CGWindowID: CGRect]>
    private let window: (CGWindowID) -> (any Window)?

    init(
        focusedWindow: OperationCache<WindowSnapshot?>,
        onScreenWindows: OperationCache<[CGWindowID: CGRect]>,
        window: @escaping (CGWindowID) -> (any Window)?
    ) {
        self.focusedWindow = focusedWindow
        self.onScreenWindows = onScreenWindows
        self.window = window
    }

    func duringOperation<T>(_ body: () -> T) -> T {
        onScreenWindows.duringOperation { focusedWindow.duringOperation(body) }
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
