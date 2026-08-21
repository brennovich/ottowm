import CoreGraphics

// A consistent read of what the OS is showing.
//
// The admission gate asks which windows are on screen several times per
// operation and the focused window is read more than once, and each ask
// would otherwise be its own IPC round trip.
final class Screen {
    private let focusedWindow: OperationCache<WindowSnapshot?>
    private let onScreenWindowIds: OperationCache<Set<CGWindowID>>
    private let window: (CGWindowID) -> (any Window)?

    init(
        focusedWindow: OperationCache<WindowSnapshot?>,
        onScreenWindowIds: OperationCache<Set<CGWindowID>>,
        window: @escaping (CGWindowID) -> (any Window)?
    ) {
        self.focusedWindow = focusedWindow
        self.onScreenWindowIds = onScreenWindowIds
        self.window = window
    }

    func duringOperation<T>(_ body: () -> T) -> T {
        onScreenWindowIds.duringOperation { focusedWindow.duringOperation(body) }
    }

    func focused() -> WindowSnapshot? {
        focusedWindow.value()
    }

    func shows(_ windowId: CGWindowID) -> Bool {
        onScreenWindowIds.value().contains(windowId)
    }

    func showsAny(_ windowIds: Set<CGWindowID>) -> Bool {
        !onScreenWindowIds.value().isDisjoint(with: windowIds)
    }

    func snapshot(of windowId: CGWindowID) -> WindowSnapshot? {
        window(windowId)?.snapshot()
    }

    func tabCount(of windowId: CGWindowID) -> Int {
        window(windowId)?.tabCount() ?? 1
    }
}
