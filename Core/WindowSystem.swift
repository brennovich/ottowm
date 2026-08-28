import CoreGraphics

/// A consistent read of what the OS shows.
///
/// One engine operation reads the focused window and the on-screen windows several times,
/// and each read costs axMessagingTimeoutSeconds against a hung application. Both are read
/// once per operation, so the cost is bounded and every decision in the operation sees the
/// same screen. The on-screen read carries each window's frame, so `frame(of:)` costs
/// nothing on top of it. `snapshot(of:)` and `tabCount(of:)` are not cached; each call is
/// a fresh read.
///
/// `focused()` is not a pure read: the injected reader may register and subscribe the
/// window it finds (the app wires it to `KnownWindows.adoptFocused()`). The cache bounds
/// that to once per operation.
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

    func frame(of windowId: CGWindowID) -> CGRect? {
        onScreenWindows.value()[windowId]
    }

    /// The frames of the given windows, keeping only the ones on screen.
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
