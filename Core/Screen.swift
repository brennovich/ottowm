import CoreGraphics

// A consistent read of what the OS is showing.
//
// The focused window comes back through the accessibility API, where an
// application that has stopped answering charges axMessagingTimeoutSeconds for
// every round trip its window costs. A single operation reads the focused
// window more than once and asks the admission gate which windows are on
// screen several times over, so holding one read for the length of an
// operation is what keeps a hung application from spending a hotkey's
// responsiveness again and again. That every decision within an operation then
// sees the same screen, and that the IPC happens once, come with it.
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
