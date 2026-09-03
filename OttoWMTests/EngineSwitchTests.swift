import CoreGraphics
import XCTest

final class EngineSwitchTests: EngineTestCase {
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

        XCTAssertEqual(parkedWindows.placement(of: 200), .parked)

        engine.switchToWorkspace(2)

        XCTAssertEqual(parkedWindows.placement(of: 100), .parked)
        XCTAssertEqual(parkedWindows.placement(of: 200), .active)
        XCTAssertEqual(workspaces.current, 2)
    }

    func testSwitchPlacesEveryWindowInOneCall() {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)
        desktop.clearPlaceCalls()

        engine.switchToWorkspace(2)

        XCTAssertEqual(desktop.placeBatches.map(Set.init), [[200, 100]])
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

    func testBringToFrontInducedFocusDoesNotSwitchAwayFromEmptyWorkspace() {
        [72, 88, 187].forEach { create(StubWindow(id: $0)) }
        offScreenWindowIds = [72, 88, 187]

        engine.switchToWorkspace(3)

        XCTAssertEqual(windows.values.reduce(0) { $0 + $1.focusCount }, 1)

        focused = windows[187]
        engine.handle(.focused(windows[187]!.snapshot()))

        XCTAssertEqual(workspaces.current, 3)
    }

    func testWindowThatLeftTheDesktopIsDropped() {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        focused = nil
        offScreenWindowIds = [100]
        engine.switchToWorkspace(2)

        XCTAssertEqual(workspaces.allWindowIds, [200])
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
    }

    func testWindowsAreNotDroppedWhileAnotherNativeSpaceIsInFront() {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        focused = nil
        offScreenWindowIds = [100, 200]
        engine.switchToWorkspace(2)

        XCTAssertEqual(workspaces.allWindowIds, [100, 200])
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
        XCTAssertEqual(parkedWindows.placement(of: 200), .parked)

        engine.switchToWorkspace(1)

        XCTAssertEqual(parkedWindows.placement(of: 200), .active)
    }

    func testSwitchReadsTheFocusedWindowAndTheScreenOnce() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        focused = win1
        focusedReadCount = 0
        onScreenReadCount = 0
        engine.switchToWorkspace(2)

        XCTAssertEqual(focusedReadCount, 1)
        XCTAssertEqual(onScreenReadCount, 1)
    }

    func testSwitchDropsTheRememberedWindowThatDiedMidOperationAndFocusesALiveOne() {
        create(StubWindow(id: 100))
        let live = create(StubWindow(id: 200))
        let doomed = create(StubWindow(id: 300))
        moveFocusedWindow(live, to: 2)
        moveFocusedWindow(doomed, to: 2)

        windows[300] = nil
        focused = nil
        engine.switchToWorkspace(2)

        XCTAssertEqual(workspaces.current, 2)
        XCTAssertEqual(parkedWindows.placement(of: 100), .parked)
        XCTAssertNil(workspaces.workspace(for: 300))
        XCTAssertEqual(live.focusCount, 1)
    }
}
