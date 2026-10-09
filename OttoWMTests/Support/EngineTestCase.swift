import CoreGraphics
import Foundation
import XCTest

/// The fixture the engine test cases share: a stub desktop and one real `Workspaces` over the
/// window system of `WindowSystemTestCase`.
class EngineTestCase: WindowSystemTestCase {
    var screenIsLocked = false
    var scheduledRetries: [(delay: TimeInterval, work: () -> Void)] = []
    let tabFrame = CGRect(x: 400, y: 0, width: 800, height: 600)

    lazy var workspaces = Workspaces(
        tabGroups: TabGroups(
            tabCount: { [weak self] id in self?.windows[id]?.tabCount() ?? 1 },
            frame: { [weak self] id in self?.windows[id]?.movableFrame() }
        )
    )

    let parkedWindows = ParkedWindows()
    lazy var originalFrames = OriginalFrames(
        tabs: { [weak self] id in self?.workspaces.tabGroupMembers(of: id) ?? [id] }
    )

    let anchor = StubAnchor()
    lazy var desktop = StubDesktop(window: { [weak self] id in self?.windows[id] }, anchor: anchor)
    let layouts = DisplayLayouts()

    private lazy var scheduleRetry: (TimeInterval, @escaping () -> Void) -> Void = { [weak self] delay, work in
        self?.scheduledRetries.append((delay, work))
    }

    lazy var admission = Admission(windowSystem: windowSystem, workspaces: workspaces)

    lazy var placement = WindowPlacement(
        desktop: desktop,
        windowSystem: windowSystem,
        workspaces: workspaces,
        admission: admission,
        parkedWindows: parkedWindows,
        originalFrames: originalFrames,
        layouts: layouts
    )

    lazy var enrollment = WindowEnrollment(
        windowSystem: windowSystem,
        workspaces: workspaces,
        placement: placement,
        scheduleRetry: scheduleRetry
    )

    lazy var navigation = Navigation(
        desktop: desktop,
        windowSystem: windowSystem,
        workspaces: workspaces,
        placement: placement,
        enrollment: enrollment
    )

    lazy var fullScreenReturns = FullScreenReturns(
        windowSystem: windowSystem,
        workspaces: workspaces,
        placement: placement,
        navigation: navigation,
        scheduleRetry: scheduleRetry
    )

    lazy var engine = Engine(
        desktop: desktop,
        windowSystem: windowSystem,
        workspaces: workspaces,
        placement: placement,
        enrollment: enrollment,
        navigation: navigation,
        fullScreenReturns: fullScreenReturns,
        screenIsLocked: { [weak self] in self?.screenIsLocked ?? false }
    )

    @discardableResult
    func runScheduledRetries(limit: Int = 10) -> [TimeInterval] {
        var delays: [TimeInterval] = []
        for _ in 0 ..< limit where !scheduledRetries.isEmpty {
            let retry = scheduledRetries.removeFirst()
            delays.append(retry.delay)
            retry.work()
        }
        return delays
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
}
