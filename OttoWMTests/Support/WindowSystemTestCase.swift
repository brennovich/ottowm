import CoreGraphics
import XCTest

/// The fixture the engine and `Displays` test cases share: a window system over a dictionary of
/// `StubWindow`s, and a `SavedState` builder.
class WindowSystemTestCase: XCTestCase {
    var windows: [CGWindowID: StubWindow] = [:]
    var focused: StubWindow?
    var focusedReadCount = 0
    var onScreenReadCount = 0
    var offScreenWindowIds: Set<CGWindowID> = []

    lazy var windowSystem = WindowSystem(
        focusedWindow: OperationCache { [weak self] in
            guard let self else { return nil }
            self.focusedReadCount += 1
            return self.focused?.snapshot()
        },
        onScreenWindows: OperationCache { [weak self] in
            guard let self else { return [:] }
            self.onScreenReadCount += 1
            return self.windows.values
                .filter { !self.offScreenWindowIds.contains($0.id) }
                .reduce(into: [CGWindowID: CGRect]()) { $0[$1.id] = $1.frame }
        },
        window: { [weak self] id in self?.windows[id] }
    )

    @discardableResult
    func add(_ window: StubWindow) -> StubWindow {
        windows[window.id] = window
        return window
    }

    func savedState(
        current: Int = 1,
        _ assignments: [(window: StubWindow, workspace: Int)],
        parked: [CGWindowID: CGRect] = [:],
        original: [CGWindowID: CGRect] = [:],
        on display: Display = .standard
    ) -> SavedState {
        var workspaces: [Int: Workspace] = [:]
        for (window, workspace) in assignments {
            workspaces[workspace, default: Workspace()].add(window.id)
        }

        return SavedState(
            display: display,
            workspaces: Workspaces.Record(current: current, workspaces: workspaces),
            parkedWindows: parked,
            originalFrames: original
        )
    }
}
