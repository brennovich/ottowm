import CoreGraphics

/// A consistent read of what the OS is showing.
///
/// A hung application costs axMessagingTimeoutSeconds per AX round trip, and a
/// single engine operation reads the focused window and the on-screen list
/// several times over. Caching one read for the length of an operation bounds
/// that cost, and every decision in the operation sees the same screen.
final class WindowSystem {
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
