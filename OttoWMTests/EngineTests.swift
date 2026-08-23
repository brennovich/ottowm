import CoreGraphics
import XCTest

final class EngineTests: XCTestCase {
    private var windows: [CGWindowID: StubWindow] = [:]
    private var focused: StubWindow?
    private var focusedReadCount = 0
    private var offScreenWindowIds: Set<CGWindowID> = []
    private var screenIsLocked = false
    private let workspaces = Workspaces()

    private lazy var desktop = StubDesktop(window: { [weak self] id in self?.windows[id] })

    private lazy var engine = Engine(
        desktop: desktop,
        screen: Screen(
            focusedWindow: OperationCache { [weak self] in
                guard let self else { return nil }
                self.focusedReadCount += 1
                return self.focused?.snapshot()
            },
            onScreenWindowIds: OperationCache { [weak self] in
                guard let self else { return [] }
                return Set(self.windows.keys).subtracting(self.offScreenWindowIds)
            },
            window: { [weak self] id in self?.windows[id] }
        ),
        workspaces: workspaces,
        screenIsLocked: { [weak self] in self?.screenIsLocked ?? false }
    )

    @discardableResult
    private func add(_ window: StubWindow) -> StubWindow {
        windows[window.id] = window
        return window
    }

    @discardableResult
    private func create(_ window: StubWindow) -> StubWindow {
        add(window)
        engine.handle(.created(window.snapshot()))
        return window
    }

    private func moveFocusedWindow(_ window: StubWindow, to workspace: Int) {
        focused = window
        engine.moveFocusedWindow(toWorkspace: workspace)
    }

    func testStartRecoversAndSeedsWindowsIntoWorkspaceOne() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))

        engine.start(windows: [win1.snapshot(), win2.snapshot()])

        XCTAssertEqual(desktop.recoverCount, 1)
        XCTAssertEqual(desktop.recoveredWindowIds, [100, 200])
        XCTAssertEqual(workspaces.allWindowIds, [100, 200])
        XCTAssertEqual(workspaces.currentWorkspace, 1)
    }

    func testStopBringsEveryParkedWindowBack() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win1, to: 2)
        moveFocusedWindow(win2, to: 3)

        engine.stop()

        XCTAssertEqual(desktop.placement(of: 100), .active)
        XCTAssertEqual(desktop.placement(of: 200), .active)
    }

    func testInvalidWindowsAreNeverAdmitted() {
        offScreenWindowIds = [500]
        let invalid = [
            add(StubWindow(id: 0)),
            add(StubWindow(id: 300, isStandard: false, hasMinimizeButton: false)),
            add(StubWindow(id: 400, isFullScreen: true)),
            add(StubWindow(id: 500)),
            add(StubWindow(id: 600, isMinimized: true)),
        ]

        engine.start(windows: invalid.map { $0.snapshot() })
        for win in invalid {
            engine.handle(.created(win.snapshot()))
            engine.handle(.focused(win.snapshot()))
        }

        XCTAssertEqual(workspaces.allWindowIds, [])
    }

    func testAWindowThatIsNotStandardButKeepsItsTitleBarButtonsIsAdmitted() {
        let win = add(StubWindow(id: 100, isStandard: false))

        engine.handle(.created(win.snapshot()))

        XCTAssertEqual(workspaces.allWindowIds, [100])
    }

    func testCreatedWindowIsAssignedToCurrentWorkspace() {
        engine.switchToWorkspace(2)
        create(StubWindow(id: 100))

        XCTAssertEqual(workspaces.allWindowIds, [100])

        engine.switchToWorkspace(1)

        XCTAssertEqual(desktop.placement(of: 100), .storage)
    }

    func testFocusedUnknownWindowIsAssignedToCurrentWorkspace() {
        let win = add(StubWindow(id: 100))

        engine.handle(.focused(win.snapshot()))

        XCTAssertEqual(workspaces.allWindowIds, [100])
    }

    func testWindowCreatedOnAnotherNativeSpaceIsIgnored() {
        create(StubWindow(id: 100))
        offScreenWindowIds = [100]
        desktop.clearPlaceCalls()

        create(StubWindow(id: 200))

        XCTAssertEqual(workspaces.allWindowIds, [100])
        XCTAssertTrue(desktop.placeCalls.isEmpty)
    }

    func testWindowFocusedOnAnotherNativeSpaceIsNotAdopted() {
        create(StubWindow(id: 100))
        offScreenWindowIds = [100]
        let win = add(StubWindow(id: 200))

        focused = win
        engine.handle(.focused(win.snapshot()))

        XCTAssertEqual(workspaces.allWindowIds, [100])
        XCTAssertEqual(workspaces.currentWorkspace, 1)
    }

    func testFocusedWindowIsRememberedPerWorkspaceAcrossSwitches() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        engine.handle(.focused(win1.snapshot()))

        engine.switchToWorkspace(2)
        engine.switchToWorkspace(1)

        XCTAssertEqual(win1.focusCount, 1)
        XCTAssertEqual(win2.focusCount, 0)
    }

    func testSwitchHidesCurrentWorkspaceWindowsAndShowsTargetWindows() {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        XCTAssertEqual(desktop.placement(of: 200), .storage)

        engine.switchToWorkspace(2)

        XCTAssertEqual(desktop.placement(of: 100), .storage)
        XCTAssertEqual(desktop.placement(of: 200), .active)
        XCTAssertEqual(workspaces.currentWorkspace, 2)
    }

    func testSwitchToSameWorkspaceOnFrontmostDesktopIsNoOp() {
        let win = create(StubWindow(id: 100))
        desktop.clearPlaceCalls()

        engine.switchToWorkspace(1)

        XCTAssertTrue(desktop.placeCalls.isEmpty)
        XCTAssertEqual(win.focusCount, 0)
    }

    func testSwitchToSameWorkspaceOffDesktopRestoresFocus() {
        let win = create(StubWindow(id: 100))
        offScreenWindowIds = [100]

        engine.switchToWorkspace(1)

        XCTAssertEqual(win.focusCount, 1)
    }

    func testSwitchToNonEmptyWorkspaceOffDesktopRestoresItsWindows() {
        let win = create(StubWindow(id: 700))
        moveFocusedWindow(win, to: 2)
        offScreenWindowIds = [700]

        engine.switchToWorkspace(2)

        XCTAssertEqual(win.focusCount, 1)
        XCTAssertEqual(desktop.placement(of: 700), .active)
    }

    func testSwitchWithNoManagedWindowsIsTreatedAsOnDesktop() {
        engine.switchToWorkspace(2)

        XCTAssertEqual(workspaces.currentWorkspace, 2)
        XCTAssertTrue(desktop.placeCalls.isEmpty)
    }

    func testBringToFrontInducedFocusDoesNotSwitchAwayFromEmptyWorkspace() {
        [72, 88, 187].forEach { create(StubWindow(id: $0)) }
        offScreenWindowIds = [72, 88, 187]

        engine.switchToWorkspace(3)

        XCTAssertEqual(windows.values.reduce(0) { $0 + $1.focusCount }, 1)

        engine.handle(.focused(windows[187]!.snapshot()))

        XCTAssertEqual(workspaces.currentWorkspace, 3)
    }

    func testSwitchFromAnotherNativeSpaceDoesNotAdoptTheWindowItShows() {
        let win1 = create(StubWindow(id: 100))
        offScreenWindowIds = [100]
        let win2 = add(StubWindow(id: 200))

        focused = win2
        engine.switchToWorkspace(2)

        XCTAssertEqual(workspaces.allWindowIds, [100])
        XCTAssertEqual(win1.focusCount, 1)
        XCTAssertEqual(win2.focusCount, 0)
    }

    func testWindowThatLeftTheDesktopIsDropped() {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        focused = nil
        offScreenWindowIds = [100]
        engine.switchToWorkspace(2)

        XCTAssertEqual(workspaces.allWindowIds, [200])
        XCTAssertEqual(desktop.forgottenWindowIds, [100])
    }

    func testParkedWindowTheScreenStopsShowingIsNotDropped() {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        let win3 = create(StubWindow(id: 300))
        moveFocusedWindow(win2, to: 2)
        moveFocusedWindow(win3, to: 2)

        focused = nil
        offScreenWindowIds = [300]
        engine.switchToWorkspace(3)

        XCTAssertEqual(workspaces.workspace(for: 300), 2)
        XCTAssertTrue(desktop.forgottenWindowIds.isEmpty)
    }

    func testWindowsAreNotDroppedWhileAnotherNativeSpaceIsInFront() {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        focused = nil
        offScreenWindowIds = [100, 200]
        engine.switchToWorkspace(2)

        XCTAssertEqual(workspaces.allWindowIds, [100, 200])
        XCTAssertTrue(desktop.forgottenWindowIds.isEmpty)
    }

    func testSwitchingAwayCapturesCurrentFocusBeforeLeaving() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        engine.handle(.focused(win2.snapshot()))

        focused = win1
        engine.switchToWorkspace(2)

        focused = nil
        engine.switchToWorkspace(1)

        XCTAssertEqual(win1.focusCount, 1)
        XCTAssertEqual(win2.focusCount, 0)
    }

    func testWindowDiscoveredWhileSwitchingJoinsTheWorkspaceItWasVisibleIn() {
        create(StubWindow(id: 100))
        add(StubWindow(id: 200))

        focused = windows[200]
        engine.switchToWorkspace(2)

        XCTAssertEqual(workspaces.windowIds(in: 1), [100, 200])
        XCTAssertEqual(desktop.placement(of: 200), .storage)

        engine.switchToWorkspace(1)

        XCTAssertEqual(desktop.placement(of: 200), .active)
    }

    func testSwitchReadsTheFocusedWindowOnce() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        focused = win1
        focusedReadCount = 0
        engine.switchToWorkspace(2)

        XCTAssertEqual(focusedReadCount, 1)
    }

    func testSwitchStillCompletesWhenTheRememberedWindowDiedMidOperation() {
        create(StubWindow(id: 100))
        let doomed = create(StubWindow(id: 200))
        moveFocusedWindow(doomed, to: 2)

        windows[200] = nil
        focused = nil
        engine.switchToWorkspace(2)

        XCTAssertEqual(workspaces.currentWorkspace, 2)
        XCTAssertEqual(desktop.placement(of: 100), .storage)
        XCTAssertEqual(doomed.focusCount, 0)
    }

    func testManualNavigationToHiddenWindowSwitchesToItsWorkspace() {
        let win = add(StubWindow(id: 700))
        engine.start(windows: [win.snapshot()])
        engine.switchToWorkspace(2)

        XCTAssertEqual(desktop.placement(of: 700), .storage)

        focused = win
        desktop.manualNavigationCallback?(700)

        XCTAssertEqual(workspaces.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 700), .active)
    }

    func testFocusedStorageWindowSwitchesToItsWorkspace() {
        let win = create(StubWindow(id: 700))
        engine.switchToWorkspace(2)

        XCTAssertEqual(desktop.placement(of: 700), .storage)

        focused = win
        engine.handle(.focused(win.snapshot()))

        XCTAssertEqual(workspaces.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 700), .active)
    }

    func testStaleFocusEventForStorageWindowIsIgnored() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        focused = win1
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 200), .storage)
    }

    func testFocusEchoFromTheWorkspaceLeftDoesNotBounceBack() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)
        focused = win1

        engine.switchToWorkspace(2)
        engine.handle(.focused(win1.snapshot()))

        XCTAssertEqual(workspaces.currentWorkspace, 2)
        XCTAssertEqual(desktop.placement(of: 100), .storage)
        XCTAssertEqual(desktop.placement(of: 200), .active)
    }

    func testFocusedStorageWindowDoesNotSwitchWhileCurrentWorkspaceIsClosing() {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        windows[100] = nil
        focused = win2
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 200), .storage)
    }

    func testFocusedStorageWindowDoesNotSwitchWhenCurrentWorkspaceWindowClosedBeforeItsDestroyedEvent() {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        offScreenWindowIds = [100]
        focused = win2
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 200), .storage)
    }

    func testFocusedStorageWindowSwitchesWhenCurrentWorkspaceWindowIsOnlyMinimized() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        win1.isMinimized = true
        offScreenWindowIds = [100]
        focused = win2
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.currentWorkspace, 2)
        XCTAssertEqual(desktop.placement(of: 200), .active)
    }

    func testMoveFocusedWindowToAnotherWorkspaceParksIt() {
        let win = create(StubWindow(id: 100))

        moveFocusedWindow(win, to: 2)

        XCTAssertEqual(desktop.placement(of: 100), .storage)
    }

    func testMoveFocusedWindowAwayHandsFocusToAWindowLeftBehind() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))

        moveFocusedWindow(win2, to: 2)

        XCTAssertEqual(win1.focusCount, 1)
        XCTAssertEqual(win2.focusCount, 0)
    }

    func testMoveWindowToWorkspaceDoesNothingWithoutFocusedWindow() {
        create(StubWindow(id: 100))
        desktop.clearPlaceCalls()

        engine.moveFocusedWindow(toWorkspace: 2)

        XCTAssertTrue(desktop.placeCalls.isEmpty)
        XCTAssertEqual(desktop.placement(of: 100), .active)
    }

    func testMoveWindowToWorkspaceIgnoresInvalidTargetOrWindow() {
        focused = add(StubWindow(id: 100))
        engine.moveFocusedWindow(toWorkspace: 0)

        focused = add(StubWindow(id: 200, isFullScreen: true))
        engine.moveFocusedWindow(toWorkspace: 2)

        XCTAssertTrue(desktop.placeCalls.isEmpty)
        XCTAssertEqual(workspaces.allWindowIds, [])
    }

    func testMoveWindowToCurrentWorkspaceRestoresIt() {
        let win = create(StubWindow(id: 100))
        focused = win

        engine.moveFocusedWindow(toWorkspace: 2)

        XCTAssertEqual(desktop.placement(of: 100), .storage)

        engine.moveFocusedWindow(toWorkspace: 1)

        XCTAssertEqual(desktop.placement(of: 100), .active)
    }

    func testStartGroupsTabsAgainstTheFrameTheyWereRecoveredTo() {
        let hiddenEdge = CGRect(x: 1791, y: 1082, width: 908, height: 798)
        let recovered = CGRect(x: 442, y: 161, width: 908, height: 798)
        let parkedTab = add(StubWindow(id: 300, appName: "Terminal", frame: hiddenEdge, tabCount: 2))
        desktop.recoveredFrames = [300: recovered]

        engine.start(windows: [parkedTab.snapshot()])
        let lateTab = add(StubWindow(id: 301, appName: "Terminal", frame: recovered, tabCount: 2))
        engine.handle(.focused(lateTab.snapshot()))

        workspaces.moveWindowToWorkspace(300, 2)
        XCTAssertEqual(workspaces.workspace(for: 301), 2)
    }

    func testTabDiscoveredDuringASwitchStaysInItsGroupsWorkspace() {
        let tabFrame = CGRect(x: 400, y: 0, width: 800, height: 600)
        create(StubWindow(id: 300, appName: "Terminal", frame: tabFrame, tabCount: 2))
        let lateTab = add(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))
        focused = lateTab

        engine.switchToWorkspace(2)

        XCTAssertEqual(workspaces.workspace(for: 301), 1)
        XCTAssertEqual(desktop.placement(of: 301), .storage)
    }

    func testFocusingATabOfAGroupParkedElsewhereFollowsTheUserToIt() {
        let tabFrame = CGRect(x: 400, y: 0, width: 800, height: 600)
        create(StubWindow(id: 300, appName: "Terminal", frame: tabFrame, tabCount: 2))
        engine.switchToWorkspace(2)

        let lateTab = add(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))
        focused = lateTab
        engine.handle(.focused(lateTab.snapshot()))

        XCTAssertEqual(workspaces.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 301), .active)
    }

    func testDestroyedWindowRestoresFocusToPreviousWindow() {
        let win1 = create(StubWindow(id: 100))
        engine.handle(.focused(win1.snapshot()))
        create(StubWindow(id: 200))

        windows[200] = nil
        engine.handle(.destroyed(200))

        XCTAssertEqual(win1.focusCount, 1)
        XCTAssertEqual(desktop.forgottenWindowIds, [200])
        XCTAssertEqual(workspaces.allWindowIds, [100])
    }

    func testWindowEventsAreIgnoredWhileTheScreenIsLocked() {
        let win = create(StubWindow(id: 100))
        engine.switchToWorkspace(2)
        screenIsLocked = true

        engine.handle(.destroyed(100))
        engine.handle(.minimized(100))
        engine.handle(.created(add(StubWindow(id: 200)).snapshot()))

        XCTAssertEqual(workspaces.allWindowIds, [100])
        XCTAssertEqual(desktop.forgottenWindowIds, [])
        XCTAssertEqual(desktop.placement(of: win.id), .storage)
    }

    func testWindowEventsAreHandledOnceTheScreenIsUnlocked() {
        create(StubWindow(id: 100))
        screenIsLocked = true
        engine.handle(.destroyed(100))
        screenIsLocked = false

        engine.handle(.destroyed(100))

        XCTAssertEqual(workspaces.allWindowIds, [])
        XCTAssertEqual(desktop.forgottenWindowIds, [100])
    }

    func testDestroyedTabbedWindowDoesNotStealFocus() {
        let tabFrame = CGRect(x: 400, y: 0, width: 800, height: 600)
        let tab1 = create(StubWindow(id: 300, appName: "Terminal", frame: tabFrame))
        engine.handle(.focused(tab1.snapshot()))
        let tab2 = create(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))
        engine.handle(.focused(tab2.snapshot()))
        let other = create(StubWindow(id: 100))

        windows[301] = nil
        engine.handle(.destroyed(301))

        XCTAssertEqual(tab1.focusCount, 0)
        XCTAssertEqual(other.focusCount, 0)
    }

    func testSwitchDropsTheFocusedWindowThatWentFullScreen() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        engine.handle(.focused(win2.snapshot()))

        win2.isFullScreen = true
        focused = win2
        offScreenWindowIds = [100]
        engine.switchToWorkspace(1)

        XCTAssertEqual(workspaces.allWindowIds, [100])
        XCTAssertEqual(desktop.forgottenWindowIds, [200])
        XCTAssertEqual(win1.focusCount, 1)
    }

    func testWindowBackFromFullScreenReturnsToTheWorkspaceItLeftAndTakesTheDesktopThere() {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        win2.isFullScreen = true
        focused = win2
        offScreenWindowIds = [100]
        engine.switchToWorkspace(1)
        engine.switchToWorkspace(2)

        win2.isFullScreen = false
        offScreenWindowIds = []
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.workspace(for: 200), 1)
        XCTAssertEqual(workspaces.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 200), .active)
    }

    func testWindowFoundBackFromFullScreenWhileRestoringFocusReturnsToTheWorkspaceItLeft() {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        win2.isFullScreen = true
        focused = win2
        offScreenWindowIds = [100]
        engine.switchToWorkspace(1)
        engine.switchToWorkspace(2)
        offScreenWindowIds = []
        create(StubWindow(id: 300))

        win2.isFullScreen = false
        windows[300] = nil
        engine.handle(.destroyed(300))

        XCTAssertEqual(workspaces.workspace(for: 200), 1)
        XCTAssertEqual(workspaces.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 200), .active)
        XCTAssertEqual(desktop.placement(of: 100), .active)
    }

    func testMovingAWindowBackFromFullScreenOverridesTheWorkspaceItLeft() {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        win2.isFullScreen = true
        focused = win2
        offScreenWindowIds = [100]
        engine.switchToWorkspace(1)
        engine.switchToWorkspace(2)

        win2.isFullScreen = false
        offScreenWindowIds = []
        engine.moveFocusedWindow(toWorkspace: 3)
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.workspace(for: 200), 3)
        XCTAssertEqual(workspaces.currentWorkspace, 2)
    }

    func testWindowThatWasNeverManagedBeforeGoingFullScreenJoinsTheCurrentWorkspace() {
        create(StubWindow(id: 100))
        engine.switchToWorkspace(2)
        let win2 = add(StubWindow(id: 200, isFullScreen: true))
        focused = win2

        win2.isFullScreen = false
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.workspace(for: 200), 2)
        XCTAssertEqual(workspaces.currentWorkspace, 2)
    }

    func testMinimizedWindowIsDroppedFromItsWorkspace() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))

        win2.isMinimized = true
        engine.handle(.minimized(200))

        XCTAssertEqual(workspaces.allWindowIds, [100])
        XCTAssertEqual(desktop.forgottenWindowIds, [200])
        XCTAssertEqual(win1.focusCount, 1)
    }

    func testMinimizedTabGroupHandsFocusToAWindowStillOnScreen() {
        let tabFrame = CGRect(x: 400, y: 0, width: 800, height: 600)
        let tab1 = create(StubWindow(id: 300, appName: "Terminal", frame: tabFrame))
        engine.handle(.focused(tab1.snapshot()))
        let tab2 = create(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))
        engine.handle(.focused(tab2.snapshot()))
        let other = create(StubWindow(id: 100))

        tab1.isMinimized = true
        tab2.isMinimized = true
        engine.handle(.minimized(301))

        XCTAssertEqual(workspaces.allWindowIds, [100])
        XCTAssertEqual(desktop.forgottenWindowIds, [300, 301])
        XCTAssertEqual(other.focusCount, 1)
        XCTAssertEqual(tab1.focusCount, 0)
    }

    func testMinimizedWindowIsLeftAloneWhenItsWorkspaceComesBack() {
        let win = create(StubWindow(id: 100))
        moveFocusedWindow(win, to: 2)
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
        let win = create(StubWindow(id: 100))
        moveFocusedWindow(win, to: 2)
        engine.switchToWorkspace(2)
        win.isMinimized = true
        engine.handle(.minimized(100))
        engine.switchToWorkspace(1)

        win.isMinimized = false
        engine.handle(.unminimized(win.snapshot()))

        XCTAssertEqual(workspaces.allWindowIds, [100])

        engine.switchToWorkspace(2)

        XCTAssertEqual(desktop.placement(of: 100), .storage)
    }

    func testHandleActionSwitchesWorkspace() {
        create(StubWindow(id: 100))

        engine.handle(Action.switchToWorkspace(2))

        XCTAssertEqual(workspaces.currentWorkspace, 2)
        XCTAssertEqual(desktop.placement(of: 100), .storage)
    }

    func testHandleActionMovesFocusedWindowToWorkspace() {
        let win = create(StubWindow(id: 100))
        focused = win

        engine.handle(Action.moveWindowToWorkspace(2))

        XCTAssertEqual(desktop.placement(of: 100), .storage)
        XCTAssertEqual(workspaces.workspace(for: 100), 2)
    }

    func testTabSiblingKeepsFocusWhenSeparateWindowCloses() {
        let tabFrame = CGRect(x: 400, y: 0, width: 800, height: 600)
        let tab1 = create(StubWindow(id: 300, appName: "Terminal", frame: tabFrame))
        let tab2 = create(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))
        engine.handle(.focused(tab1.snapshot()))
        let other = create(StubWindow(id: 100))
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
