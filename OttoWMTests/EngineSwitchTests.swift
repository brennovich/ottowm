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

    func testWindowThatLeftTheDesktopIsDropped() {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        focused = nil
        offScreenWindowIds = [100]
        engine.switchToWorkspace(2)

        XCTAssertEqual(workspaces.allWindowIds, [200])
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

        XCTAssertEqual(live.focusCount, 1)
    }
}
