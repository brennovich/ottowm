import CoreGraphics
import XCTest

final class EngineTests: XCTestCase {
    private var desktop = StubDesktop()
    private var windows: [CGWindowID: StubWindow] = [:]
    private var focused: StubWindow?
    private var focusedReadCount = 0
    private var offScreenWindowIds: Set<CGWindowID> = []

    private lazy var engine = Engine(
        desktop: desktop,
        window: { [weak self] id in self?.windows[id] },
        focusedWindow: OperationCache { [weak self] in
            guard let self else { return nil }
            self.focusedReadCount += 1
            return self.focused?.snapshot()
        },
        onScreenWindows: OperationCache { [weak self] in
            guard let self else { return [] }
            return Set(self.windows.keys).subtracting(self.offScreenWindowIds)
        }
    )

    private func makeWindow(
        _ id: CGWindowID,
        appName: String = "App",
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
        tabCount: Int = 1,
        isStandard: Bool = true,
        isFullScreen: Bool = false,
        isMinimized: Bool = false
    ) -> StubWindow {
        let window = StubWindow(
            id: id,
            tabCount: tabCount,
            frame: frame,
            appName: appName,
            isMinimized: isMinimized,
            isStandard: isStandard,
            isFullScreen: isFullScreen
        )
        windows[id] = window
        return window
    }

    func testStartSetsUpMainScreenAndSeedsWindowsIntoWorkspaceOne() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 50, y: 50, width: 400, height: 300))

        engine.start(windows: [win1.snapshot(), win2.snapshot()])

        XCTAssertEqual(desktop.setupForMainScreenCount, 1)
        XCTAssertEqual(desktop.setupWindowIds, [100, 200])
        XCTAssertEqual(engine.managedWindowIds, [100, 200])
        XCTAssertEqual(engine.currentWorkspace, 1)
    }

    func testStartSkipsInvalidWindows() {
        offScreenWindowIds = [500]
        let seeds = [
            makeWindow(0),
            makeWindow(300, isStandard: false),
            makeWindow(400, isFullScreen: true),
            makeWindow(500),
            makeWindow(600, isMinimized: true),
        ]

        engine.start(windows: seeds.map { $0.snapshot() })

        XCTAssertEqual(engine.managedWindowIds, [])
    }

    func testCreatedWindowIsAssignedToCurrentWorkspace() {
        engine.switchToWorkspace(2)
        let win = makeWindow(100)

        engine.handle(.created(win.snapshot()))

        XCTAssertEqual(engine.managedWindowIds, [100])

        engine.switchToWorkspace(1)

        XCTAssertEqual(desktop.placement(of: 100), .storage)
    }

    func testCreatedInvalidWindowIsIgnored() {
        offScreenWindowIds = [400]
        let invalidWindows = [
            makeWindow(0),
            makeWindow(200, isStandard: false),
            makeWindow(300, isFullScreen: true),
            makeWindow(400),
            makeWindow(500, isMinimized: true),
        ]

        for win in invalidWindows {
            engine.handle(.created(win.snapshot()))
        }

        XCTAssertEqual(engine.managedWindowIds, [])
    }

    func testFocusedUnknownWindowIsAssignedToCurrentWorkspace() {
        let win = makeWindow(100)

        engine.handle(.focused(win.snapshot()))

        XCTAssertEqual(engine.managedWindowIds, [100])
    }

    func testFocusedInvalidWindowIsIgnored() {
        let invalidWindows = [
            makeWindow(0),
            makeWindow(100, isMinimized: true),
        ]

        for win in invalidWindows {
            engine.handle(.focused(win.snapshot()))
        }

        XCTAssertEqual(engine.managedWindowIds, [])
    }

    func testFocusedWindowIsRememberedPerWorkspaceAcrossSwitches() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        engine.handle(.focused(win1.snapshot()))

        engine.switchToWorkspace(2)
        engine.switchToWorkspace(1)

        XCTAssertEqual(win1.focusCount, 1)
        XCTAssertEqual(win2.focusCount, 0)
    }

    func testSwitchHidesCurrentWorkspaceWindowsAndShowsTargetWindows() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        engine.moveWindowToWorkspace(win2.snapshot(), 2)

        XCTAssertEqual(desktop.placement(of: 200), .storage)

        engine.switchToWorkspace(2)

        XCTAssertEqual(desktop.placement(of: 100), .storage)
        XCTAssertEqual(desktop.placement(of: 200), .active)
        XCTAssertEqual(engine.currentWorkspace, 2)
    }

    func testSwitchToSameWorkspaceOnFrontmostDesktopIsNoOp() {
        let win = makeWindow(100)
        engine.handle(.created(win.snapshot()))

        engine.switchToWorkspace(1)

        XCTAssertTrue(desktop.placeCalls.isEmpty)
        XCTAssertEqual(win.focusCount, 0)
    }

    func testSwitchToSameWorkspaceOffDesktopRestoresFocus() {
        let win = makeWindow(100)
        engine.handle(.created(win.snapshot()))
        offScreenWindowIds = [100]

        engine.switchToWorkspace(1)

        XCTAssertEqual(win.focusCount, 1)
    }

    func testSwitchToNonEmptyWorkspaceOffDesktopRestoresItsWindows() {
        let win = makeWindow(700)
        engine.handle(.created(win.snapshot()))
        engine.moveWindowToWorkspace(win.snapshot(), 2)
        offScreenWindowIds = [700]

        engine.switchToWorkspace(2)

        XCTAssertEqual(win.focusCount, 1)
        XCTAssertEqual(desktop.placement(of: 700), .active)
    }

    func testSwitchWithNoManagedWindowsIsTreatedAsOnDesktop() {
        engine.switchToWorkspace(2)

        XCTAssertEqual(engine.currentWorkspace, 2)
        XCTAssertTrue(desktop.placeCalls.isEmpty)
    }

    func testBringToFrontInducedFocusDoesNotSwitchAwayFromEmptyWorkspace() {
        for win in [makeWindow(72), makeWindow(88), makeWindow(187)] {
            engine.handle(.created(win.snapshot()))
        }
        offScreenWindowIds = [72, 88, 187]

        engine.switchToWorkspace(3)

        XCTAssertEqual(windows.values.reduce(0) { $0 + $1.focusCount }, 1)

        engine.handle(.focused(windows[187]!.snapshot()))

        XCTAssertEqual(engine.currentWorkspace, 3)
    }

    func testSwitchingAwayCapturesCurrentFocusBeforeLeaving() {
        let win1 = makeWindow(100, appName: "Terminal")
        let win2 = makeWindow(200, appName: "Terminal", frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        engine.handle(.focused(win2.snapshot()))

        focused = win1
        engine.switchToWorkspace(2)

        focused = nil
        engine.switchToWorkspace(1)

        XCTAssertEqual(win1.focusCount, 1)
        XCTAssertEqual(win2.focusCount, 0)
    }

    func testSwitchReadsTheFocusedWindowOnce() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        engine.moveWindowToWorkspace(win2.snapshot(), 2)

        focused = win1
        focusedReadCount = 0
        engine.switchToWorkspace(2)

        XCTAssertEqual(focusedReadCount, 1)
    }

    func testManualNavigationToHiddenWindowSwitchesToItsWorkspace() {
        let win = makeWindow(700)
        engine.start(windows: [win.snapshot()])
        engine.switchToWorkspace(2)

        XCTAssertEqual(desktop.placement(of: 700), .storage)

        focused = win
        desktop.manualNavigationCallback?(700)

        XCTAssertEqual(engine.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 700), .active)
    }

    func testFocusedStorageWindowSwitchesToItsWorkspace() {
        let win = makeWindow(700)
        engine.handle(.created(win.snapshot()))
        engine.switchToWorkspace(2)

        XCTAssertEqual(desktop.placement(of: 700), .storage)

        focused = win
        engine.handle(.focused(win.snapshot()))

        XCTAssertEqual(engine.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 700), .active)
    }

    func testStaleFocusEventForStorageWindowIsIgnored() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        engine.moveWindowToWorkspace(win2.snapshot(), 2)

        focused = win1
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(engine.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 200), .storage)
    }

    func testFocusedStorageWindowDoesNotSwitchWhileCurrentWorkspaceIsClosing() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        engine.moveWindowToWorkspace(win2.snapshot(), 2)

        windows[100] = nil
        focused = win2
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(engine.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 200), .storage)
    }

    func testFocusedStorageWindowDoesNotSwitchWhenCurrentWorkspaceWindowClosedBeforeItsDestroyedEvent() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        engine.moveWindowToWorkspace(win2.snapshot(), 2)

        offScreenWindowIds = [100]
        focused = win2
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(engine.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 200), .storage)
    }

    func testFocusedStorageWindowSwitchesWhenCurrentWorkspaceWindowIsOnlyMinimized() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        engine.moveWindowToWorkspace(win2.snapshot(), 2)

        win1.isMinimized = true
        offScreenWindowIds = [100]
        focused = win2
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(engine.currentWorkspace, 2)
        XCTAssertEqual(desktop.placement(of: 200), .active)
    }

    func testMoveWindowToWorkspaceUsesFocusedWindowWhenNil() {
        let win = makeWindow(100)
        engine.handle(.created(win.snapshot()))
        focused = win

        engine.moveWindowToWorkspace(nil, 2)

        XCTAssertEqual(desktop.placement(of: 100), .storage)
    }

    func testMoveWindowToWorkspaceMovesExplicitWindow() {
        let win = makeWindow(200)
        engine.handle(.created(win.snapshot()))

        engine.moveWindowToWorkspace(win.snapshot(), 2)

        XCTAssertEqual(desktop.placement(of: 200), .storage)
    }

    func testMoveWindowToWorkspaceDoesNothingWithoutWindow() {
        let win = makeWindow(100)
        engine.handle(.created(win.snapshot()))

        engine.moveWindowToWorkspace(nil, 2)

        XCTAssertTrue(desktop.placeCalls.isEmpty)
        XCTAssertEqual(desktop.placement(of: 100), .active)
    }

    func testMoveWindowToWorkspaceIgnoresInvalidTarget() {
        let win = makeWindow(100)
        focused = win

        engine.moveWindowToWorkspace(nil, 0)

        XCTAssertTrue(desktop.placeCalls.isEmpty)
        XCTAssertEqual(engine.managedWindowIds, [])
    }

    func testMoveWindowToWorkspaceIgnoresInvalidWindow() {
        let win = makeWindow(100, isFullScreen: true)
        focused = win

        engine.moveWindowToWorkspace(nil, 2)

        XCTAssertTrue(desktop.placeCalls.isEmpty)
        XCTAssertEqual(engine.managedWindowIds, [])
    }

    func testMoveWindowToCurrentWorkspaceRestoresIt() {
        let win = makeWindow(100)
        engine.handle(.created(win.snapshot()))
        focused = win

        engine.moveWindowToWorkspace(nil, 2)

        XCTAssertEqual(desktop.placement(of: 100), .storage)

        engine.moveWindowToWorkspace(nil, 1)

        XCTAssertEqual(desktop.placement(of: 100), .active)
    }

    func testDestroyedWindowRestoresFocusToPreviousWindow() {
        let win1 = makeWindow(100, appName: "App1")
        let win2 = makeWindow(200, appName: "App2", frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.focused(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))

        windows[200] = nil
        engine.handle(.destroyed(200))

        XCTAssertEqual(win1.focusCount, 1)
        XCTAssertEqual(desktop.forgottenWindowIds, [200])
        XCTAssertEqual(engine.managedWindowIds, [100])
    }

    func testDestroyedTabbedWindowDoesNotStealFocus() {
        let tabFrame = CGRect(x: 400, y: 0, width: 800, height: 600)
        let tab1 = makeWindow(300, appName: "Terminal", frame: tabFrame)
        let tab2 = makeWindow(301, appName: "Terminal", frame: tabFrame, tabCount: 2)
        let other = makeWindow(100, appName: "App1")
        engine.handle(.created(tab1.snapshot()))
        engine.handle(.focused(tab1.snapshot()))
        engine.handle(.created(tab2.snapshot()))
        engine.handle(.focused(tab2.snapshot()))
        engine.handle(.created(other.snapshot()))

        windows[301] = nil
        engine.handle(.destroyed(301))

        XCTAssertEqual(tab1.focusCount, 0)
        XCTAssertEqual(other.focusCount, 0)
    }

    func testSwitchDropsTheFocusedWindowThatWentFullScreen() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        engine.handle(.focused(win2.snapshot()))

        win2.isFullScreen = true
        focused = win2
        offScreenWindowIds = [100]
        engine.switchToWorkspace(1)

        XCTAssertEqual(engine.managedWindowIds, [100])
        XCTAssertEqual(desktop.forgottenWindowIds, [200])
        XCTAssertEqual(win1.focusCount, 1)
    }

    func testWindowBackFromFullScreenJoinsTheCurrentWorkspace() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        win2.isFullScreen = true
        focused = win2
        offScreenWindowIds = [100]
        engine.switchToWorkspace(1)

        win2.isFullScreen = false
        offScreenWindowIds = []
        engine.switchToWorkspace(2)

        XCTAssertEqual(engine.managedWindowIds, [100, 200])

        engine.switchToWorkspace(1)

        XCTAssertEqual(desktop.placement(of: 200), .storage)
    }

    func testMinimizedWindowIsDroppedFromItsWorkspace() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))

        win2.isMinimized = true
        engine.handle(.minimized(200))

        XCTAssertEqual(engine.managedWindowIds, [100])
        XCTAssertEqual(desktop.forgottenWindowIds, [200])
        XCTAssertEqual(win1.focusCount, 1)
    }

    func testMinimizedWindowIsLeftAloneWhenItsWorkspaceComesBack() {
        let win = makeWindow(100)
        engine.handle(.created(win.snapshot()))
        engine.moveWindowToWorkspace(win.snapshot(), 2)
        engine.switchToWorkspace(2)

        win.isMinimized = true
        engine.handle(.minimized(100))
        let placeCalls = desktop.placeCalls.count
        let focusCount = win.focusCount

        engine.switchToWorkspace(1)
        engine.switchToWorkspace(2)

        XCTAssertEqual(desktop.placeCalls.count, placeCalls)
        XCTAssertEqual(win.focusCount, focusCount)
    }

    func testUnminimizedWindowJoinsTheCurrentWorkspace() {
        let win = makeWindow(100)
        engine.handle(.created(win.snapshot()))
        engine.moveWindowToWorkspace(win.snapshot(), 2)
        engine.switchToWorkspace(2)
        win.isMinimized = true
        engine.handle(.minimized(100))
        engine.switchToWorkspace(1)

        win.isMinimized = false
        engine.handle(.unminimized(win.snapshot()))

        XCTAssertEqual(engine.managedWindowIds, [100])

        engine.switchToWorkspace(2)

        XCTAssertEqual(desktop.placement(of: 100), .storage)
    }

    func testTabSiblingKeepsFocusWhenSeparateWindowCloses() {
        let tabFrame = CGRect(x: 400, y: 0, width: 800, height: 600)
        let tab1 = makeWindow(300, appName: "Terminal", frame: tabFrame)
        let tab2 = makeWindow(301, appName: "Terminal", frame: tabFrame, tabCount: 2)
        let other = makeWindow(100, appName: "App1")
        engine.handle(.created(tab1.snapshot()))
        engine.handle(.created(tab2.snapshot()))
        engine.handle(.focused(tab1.snapshot()))
        engine.handle(.created(other.snapshot()))
        engine.handle(.focused(other.snapshot()))

        focused = tab2
        windows[100] = nil
        engine.handle(.destroyed(100))

        XCTAssertEqual(tab1.focusCount, 0)
        XCTAssertEqual(tab2.focusCount, 0)

        focused = nil
        engine.switchToWorkspace(2)
        engine.switchToWorkspace(1)

        XCTAssertEqual(tab2.focusCount, 1)
        XCTAssertEqual(tab1.focusCount, 0)
    }
}
