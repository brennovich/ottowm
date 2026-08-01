import CoreGraphics
import XCTest

final class EngineTests: XCTestCase {
    private var desktop = StubDesktop()
    private var windows: [CGWindowID: StubWindow] = [:]
    private var focused: StubWindow?
    private var focusedReadCount = 0

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
            return Set(self.windows.keys).subtracting(self.desktop.absentWindowIds)
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

    func testStartSetsUpMainScreenAndSeedsWindowsIntoVirtualSpaceOne() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 50, y: 50, width: 400, height: 300))

        engine.start(windows: [win1.snapshot(), win2.snapshot()])

        XCTAssertEqual(desktop.setupForMainScreenCount, 1)
        XCTAssertEqual(desktop.setupWindowIds, [100, 200])
        XCTAssertEqual(engine.managedWindowIds, [100, 200])
        XCTAssertEqual(engine.currentVirtualSpace, 1)
    }

    func testStartSkipsInvalidWindows() {
        desktop.absentWindowIds = [500]
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

    func testCreatedWindowIsAssignedToCurrentVirtualSpace() {
        engine.switchToVirtualSpace(2)
        let win = makeWindow(100)

        engine.handle(.created(win.snapshot()))

        XCTAssertEqual(engine.managedWindowIds, [100])

        engine.switchToVirtualSpace(1)

        XCTAssertEqual(desktop.placement(of: 100), .storage)
    }

    func testCreatedInvalidWindowIsIgnored() {
        desktop.absentWindowIds = [400]
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

    func testFocusedUnknownWindowIsAssignedToCurrentVirtualSpace() {
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

    func testFocusedWindowIsRememberedPerVirtualSpaceAcrossSwitches() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        engine.handle(.focused(win1.snapshot()))

        engine.switchToVirtualSpace(2)
        engine.switchToVirtualSpace(1)

        XCTAssertEqual(win1.focusCount, 1)
        XCTAssertEqual(win2.focusCount, 0)
    }

    func testSwitchHidesCurrentSpaceWindowsAndShowsTargetWindows() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        engine.moveWindowToVirtualSpace(win2.snapshot(), 2)

        XCTAssertEqual(desktop.placement(of: 200), .storage)

        engine.switchToVirtualSpace(2)

        XCTAssertEqual(desktop.placement(of: 100), .storage)
        XCTAssertEqual(desktop.placement(of: 200), .active)
        XCTAssertEqual(engine.currentVirtualSpace, 2)
    }

    func testSwitchToSameVirtualSpaceOnFrontmostDesktopIsNoOp() {
        let win = makeWindow(100)
        engine.handle(.created(win.snapshot()))

        engine.switchToVirtualSpace(1)

        XCTAssertTrue(desktop.placeCalls.isEmpty)
        XCTAssertEqual(win.focusCount, 0)
    }

    func testSwitchToSameVirtualSpaceOffDesktopRestoresFocus() {
        let win = makeWindow(100)
        engine.handle(.created(win.snapshot()))
        desktop.isFrontmostValue = false

        engine.switchToVirtualSpace(1)

        XCTAssertEqual(win.focusCount, 1)
        XCTAssertEqual(desktop.bringToFrontCount, 0)
    }

    func testSwitchToNonEmptyVirtualSpaceOffDesktopRestoresFocusWithoutBringingToFront() {
        let win = makeWindow(700)
        engine.handle(.created(win.snapshot()))
        engine.moveWindowToVirtualSpace(win.snapshot(), 2)
        desktop.isFrontmostValue = false

        engine.switchToVirtualSpace(2)

        XCTAssertEqual(win.focusCount, 1)
        XCTAssertEqual(desktop.placement(of: 700), .active)
        XCTAssertEqual(desktop.bringToFrontCount, 0)
    }

    func testSwitchWithNoManagedWindowsDoesNotBringDesktopToFront() {
        desktop.isFrontmostValue = false

        engine.switchToVirtualSpace(2)
        engine.switchToVirtualSpace(2)

        XCTAssertEqual(desktop.bringToFrontCount, 0)
        XCTAssertEqual(engine.currentVirtualSpace, 2)
    }

    func testBringToFrontInducedFocusDoesNotSwitchAwayFromEmptySpace() {
        for win in [makeWindow(72), makeWindow(88), makeWindow(187)] {
            engine.handle(.created(win.snapshot()))
        }
        desktop.isFrontmostValue = false

        engine.switchToVirtualSpace(3)

        XCTAssertEqual(desktop.bringToFrontCount, 1)

        engine.handle(.focused(windows[187]!.snapshot()))

        XCTAssertEqual(engine.currentVirtualSpace, 3)
    }

    func testSwitchingAwayCapturesCurrentFocusBeforeLeaving() {
        let win1 = makeWindow(100, appName: "Terminal")
        let win2 = makeWindow(200, appName: "Terminal", frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        engine.handle(.focused(win2.snapshot()))

        focused = win1
        engine.switchToVirtualSpace(2)

        focused = nil
        engine.switchToVirtualSpace(1)

        XCTAssertEqual(win1.focusCount, 1)
        XCTAssertEqual(win2.focusCount, 0)
    }

    func testSwitchReadsTheFocusedWindowOnce() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        engine.moveWindowToVirtualSpace(win2.snapshot(), 2)

        focused = win1
        focusedReadCount = 0
        engine.switchToVirtualSpace(2)

        XCTAssertEqual(focusedReadCount, 1)
    }

    func testManualNavigationToHiddenWindowSwitchesToItsVirtualSpace() {
        let win = makeWindow(700)
        engine.start(windows: [win.snapshot()])
        engine.switchToVirtualSpace(2)

        XCTAssertEqual(desktop.placement(of: 700), .storage)

        focused = win
        desktop.manualNavigationCallback?(700)

        XCTAssertEqual(engine.currentVirtualSpace, 1)
        XCTAssertEqual(desktop.placement(of: 700), .active)
    }

    func testFocusedStorageWindowSwitchesToItsVirtualSpace() {
        let win = makeWindow(700)
        engine.handle(.created(win.snapshot()))
        engine.switchToVirtualSpace(2)

        XCTAssertEqual(desktop.placement(of: 700), .storage)

        focused = win
        engine.handle(.focused(win.snapshot()))

        XCTAssertEqual(engine.currentVirtualSpace, 1)
        XCTAssertEqual(desktop.placement(of: 700), .active)
    }

    func testStaleFocusEventForStorageWindowIsIgnored() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        engine.moveWindowToVirtualSpace(win2.snapshot(), 2)

        focused = win1
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(engine.currentVirtualSpace, 1)
        XCTAssertEqual(desktop.placement(of: 200), .storage)
    }

    func testFocusedStorageWindowDoesNotSwitchWhileCurrentSpaceIsClosing() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        engine.moveWindowToVirtualSpace(win2.snapshot(), 2)

        windows[100] = nil
        focused = win2
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(engine.currentVirtualSpace, 1)
        XCTAssertEqual(desktop.placement(of: 200), .storage)
    }

    func testFocusedStorageWindowDoesNotSwitchWhenCurrentSpaceWindowClosedBeforeItsDestroyedEvent() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        engine.moveWindowToVirtualSpace(win2.snapshot(), 2)

        desktop.absentWindowIds = [100]
        focused = win2
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(engine.currentVirtualSpace, 1)
        XCTAssertEqual(desktop.placement(of: 200), .storage)
    }

    func testFocusedStorageWindowSwitchesWhenCurrentSpaceWindowIsOnlyMinimized() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        engine.moveWindowToVirtualSpace(win2.snapshot(), 2)

        win1.isMinimized = true
        desktop.absentWindowIds = [100]
        focused = win2
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(engine.currentVirtualSpace, 2)
        XCTAssertEqual(desktop.placement(of: 200), .active)
    }

    func testMoveWindowToVirtualSpaceUsesFocusedWindowWhenNil() {
        let win = makeWindow(100)
        engine.handle(.created(win.snapshot()))
        focused = win

        engine.moveWindowToVirtualSpace(nil, 2)

        XCTAssertEqual(desktop.placement(of: 100), .storage)
    }

    func testMoveWindowToVirtualSpaceMovesExplicitWindow() {
        let win = makeWindow(200)
        engine.handle(.created(win.snapshot()))

        engine.moveWindowToVirtualSpace(win.snapshot(), 2)

        XCTAssertEqual(desktop.placement(of: 200), .storage)
    }

    func testMoveWindowToVirtualSpaceDoesNothingWithoutWindow() {
        let win = makeWindow(100)
        engine.handle(.created(win.snapshot()))

        engine.moveWindowToVirtualSpace(nil, 2)

        XCTAssertTrue(desktop.placeCalls.isEmpty)
        XCTAssertEqual(desktop.placement(of: 100), .active)
    }

    func testMoveWindowToVirtualSpaceIgnoresInvalidTarget() {
        let win = makeWindow(100)
        focused = win

        engine.moveWindowToVirtualSpace(nil, 0)

        XCTAssertTrue(desktop.placeCalls.isEmpty)
        XCTAssertEqual(engine.managedWindowIds, [])
    }

    func testMoveWindowToVirtualSpaceIgnoresInvalidWindow() {
        let win = makeWindow(100, isFullScreen: true)
        focused = win

        engine.moveWindowToVirtualSpace(nil, 2)

        XCTAssertTrue(desktop.placeCalls.isEmpty)
        XCTAssertEqual(engine.managedWindowIds, [])
    }

    func testMoveWindowToCurrentVirtualSpaceRestoresIt() {
        let win = makeWindow(100)
        engine.handle(.created(win.snapshot()))
        focused = win

        engine.moveWindowToVirtualSpace(nil, 2)

        XCTAssertEqual(desktop.placement(of: 100), .storage)

        engine.moveWindowToVirtualSpace(nil, 1)

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
        desktop.isFrontmostValue = false
        engine.switchToVirtualSpace(1)

        XCTAssertEqual(engine.managedWindowIds, [100])
        XCTAssertEqual(desktop.forgottenWindowIds, [200])
        XCTAssertEqual(win1.focusCount, 1)
    }

    func testWindowBackFromFullScreenJoinsTheCurrentVirtualSpace() {
        let win1 = makeWindow(100)
        let win2 = makeWindow(200, frame: CGRect(x: 0, y: 200, width: 800, height: 600))
        engine.handle(.created(win1.snapshot()))
        engine.handle(.created(win2.snapshot()))
        win2.isFullScreen = true
        focused = win2
        desktop.isFrontmostValue = false
        engine.switchToVirtualSpace(1)

        win2.isFullScreen = false
        desktop.isFrontmostValue = true
        engine.switchToVirtualSpace(2)

        XCTAssertEqual(engine.managedWindowIds, [100, 200])

        engine.switchToVirtualSpace(1)

        XCTAssertEqual(desktop.placement(of: 200), .storage)
    }

    func testMinimizedWindowIsDroppedFromItsVirtualSpace() {
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

    func testMinimizedWindowIsLeftAloneWhenItsVirtualSpaceComesBack() {
        let win = makeWindow(100)
        engine.handle(.created(win.snapshot()))
        engine.moveWindowToVirtualSpace(win.snapshot(), 2)
        engine.switchToVirtualSpace(2)

        win.isMinimized = true
        engine.handle(.minimized(100))
        let placeCalls = desktop.placeCalls.count
        let focusCount = win.focusCount

        engine.switchToVirtualSpace(1)
        engine.switchToVirtualSpace(2)

        XCTAssertEqual(desktop.placeCalls.count, placeCalls)
        XCTAssertEqual(win.focusCount, focusCount)
    }

    func testUnminimizedWindowJoinsTheCurrentVirtualSpace() {
        let win = makeWindow(100)
        engine.handle(.created(win.snapshot()))
        engine.moveWindowToVirtualSpace(win.snapshot(), 2)
        engine.switchToVirtualSpace(2)
        win.isMinimized = true
        engine.handle(.minimized(100))
        engine.switchToVirtualSpace(1)

        win.isMinimized = false
        engine.handle(.unminimized(win.snapshot()))

        XCTAssertEqual(engine.managedWindowIds, [100])

        engine.switchToVirtualSpace(2)

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
        engine.switchToVirtualSpace(2)
        engine.switchToVirtualSpace(1)

        XCTAssertEqual(tab2.focusCount, 1)
        XCTAssertEqual(tab1.focusCount, 0)
    }
}
