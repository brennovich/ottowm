import CoreGraphics
import XCTest

/// The fixture the engine test cases share: a stub desktop and window system over a
/// dictionary of `StubWindow`s, and one real `Workspaces`.
class EngineTestCase: XCTestCase {
    var windows: [CGWindowID: StubWindow] = [:]
    var focused: StubWindow?
    var focusedReadCount = 0
    var offScreenWindowIds: Set<CGWindowID> = []
    var screenIsLocked = false
    var quitCount = 0
    var restartCount = 0
    let workspaces = Workspaces()
    let tabFrame = CGRect(x: 400, y: 0, width: 800, height: 600)

    lazy var desktop = StubDesktop(window: { [weak self] id in self?.windows[id] })

    lazy var engine = Engine(
        desktop: desktop,
        windowSystem: WindowSystem(
            focusedWindow: OperationCache { [weak self] in
                guard let self else { return nil }
                self.focusedReadCount += 1
                return self.focused?.snapshot()
            },
            onScreenWindows: OperationCache { [weak self] in
                guard let self else { return [:] }
                return self.windows.values
                    .filter { !self.offScreenWindowIds.contains($0.id) }
                    .reduce(into: [CGWindowID: CGRect]()) { $0[$1.id] = $1.frame }
            },
            window: { [weak self] id in self?.windows[id] }
        ),
        workspaces: workspaces,
        screenIsLocked: { [weak self] in self?.screenIsLocked ?? false },
        quit: { [weak self] in self?.quit() },
        restart: { [weak self] in self?.restartCount += 1 }
    )

    @discardableResult
    func add(_ window: StubWindow) -> StubWindow {
        windows[window.id] = window
        return window
    }

    @discardableResult
    func create(_ window: StubWindow) -> StubWindow {
        add(window)
        engine.handle(.created(window.snapshot()))
        return window
    }

    func moveFocusedWindow(_ window: StubWindow, to workspace: Int) {
        focused = window
        engine.moveFocusedWindow(toWorkspace: workspace)
    }

    func createFocusedTabPair() -> (tab1: StubWindow, tab2: StubWindow, other: StubWindow) {
        let tab1 = create(StubWindow(id: 300, appName: "Terminal", frame: tabFrame))
        engine.handle(.focused(tab1.snapshot()))
        let tab2 = create(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))
        engine.handle(.focused(tab2.snapshot()))
        let other = create(StubWindow(id: 100))
        return (tab1, tab2, other)
    }

    /// Mirrors the production wiring, where Shutdown.quit stops the engine before it
    /// exits.
    private func quit() {
        engine.stop()
        quitCount += 1
    }
}
