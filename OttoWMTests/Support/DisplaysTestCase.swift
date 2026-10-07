import CoreGraphics
import XCTest

/// The fixture the `Displays` test cases share: a standard and a right display, and an engine per display over
/// `StubDesktop`s.
class DisplaysTestCase: WindowSystemTestCase {
    let onStandard = CGRect(x: 100, y: 100, width: 800, height: 600)
    let onRight = CGRect(x: 2000, y: 100, width: 800, height: 600)
    var connected: [Display] = [.standard, .right]
    var activeDisplay: DisplayID?
    var screenIsLocked = false
    var screenParametersChanged: (() -> Void)?
    var workspaces: [DisplayID: Workspaces] = [:]
    var desktops: [DisplayID: StubDesktop] = [:]
    var written: [[SavedState]] = []
    var removed: [DisplayID] = []
    let layouts = DisplayLayouts()

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
        add(StubWindow(id: id, frame: frame))
    }
}
