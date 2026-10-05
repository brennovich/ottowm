import CoreGraphics
import XCTest

/// The fixture the `Displays` test cases share: a standard and an AirPlay display, an engine per display over
/// `StubDesktop`s, and a window system over a dictionary of `StubWindow`s.
class DisplaysTestCase: XCTestCase {
    let onStandard = CGRect(x: 100, y: 100, width: 800, height: 600)
    let onAirPlay = CGRect(x: 2000, y: 100, width: 800, height: 600)
    var windows: [CGWindowID: StubWindow] = [:]
    var focused: StubWindow?
    var focusedReadCount = 0
    var onScreenReadCount = 0
    var connected: [Display] = [.standard, .airPlay]
    var activeDisplay: DisplayID?
    var screenIsLocked = false
    var screenParametersChanged: (() -> Void)?
    var workspaces: [DisplayID: Workspaces] = [:]
    var desktops: [DisplayID: StubDesktop] = [:]
    var written: [[SavedState]] = []
    var removed: [DisplayID] = []
    let layouts = DisplayLayouts()

    lazy var windowSystem = WindowSystem(
        focusedWindow: OperationCache { [weak self] in
            guard let self else { return nil }
            self.focusedReadCount += 1
            return self.focused?.snapshot()
        },
        onScreenWindows: OperationCache { [weak self] in
            guard let self else { return [:] }
            self.onScreenReadCount += 1
            return self.windows.mapValues(\.frame)
        },
        window: { [weak self] id in self?.windows[id] }
    )

    lazy var displays = makeDisplays()

    func makeDisplays() -> Displays {
        workspaces = [:]
        desktops = [:]
        return Displays(
            screens: Screens(
                all: { [weak self] in self?.connected ?? [] },
                active: { [weak self] in self?.activeDisplay },
                startWatching: { [weak self] in self?.screenParametersChanged = $0 }
            ),
            windowSystem: windowSystem,
            screenIsLocked: { [weak self] in self?.screenIsLocked ?? false },
            write: { [weak self] in self?.written.append($0) },
            removed: { [weak self] in self?.removed.append($0) },
            engine: { [weak self, layouts] display, windowSystem, save in
                let desktop = StubDesktop(window: { [weak self] id in self?.windows[id] })
                desktop.display = display
                let workspaces = Workspaces(
                    tabGroups: TabGroups(tabCount: { _ in 1 }, frame: { [weak self] id in self?.windows[id]?.movableFrame() })
                )
                self?.desktops[display.id] = desktop
                self?.workspaces[display.id] = workspaces
                let engine = Engine.system(
                    desktop: desktop,
                    windowSystem: windowSystem,
                    workspaces: workspaces,
                    layouts: layouts,
                    scheduleRetry: { _, _ in },
                    save: save
                )
                return (workspaces, desktop, engine)
            }
        )
    }

    @discardableResult
    func add(_ id: CGWindowID, frame: CGRect) -> StubWindow {
        let window = StubWindow(id: id, frame: frame)
        windows[id] = window
        return window
    }
}
