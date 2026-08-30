import CoreGraphics
import XCTest

final class EngineLifecycleTests: EngineTestCase {
    func testStartRecoversAndSeedsWindowsIntoWorkspaceOne() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))

        engine.start(windows: [win1.snapshot(), win2.snapshot()])

        XCTAssertEqual(desktop.recoverCount, 1)
        XCTAssertEqual(desktop.recoveredWindowIds, [100, 200])
        XCTAssertEqual(workspaces.allWindowIds, [100, 200])
        XCTAssertEqual(workspaces.current, 1)
    }

    func testQuitBringsEveryParkedWindowBackBeforeLeaving() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win1, to: 2)
        moveFocusedWindow(win2, to: 3)

        engine.handle(.quit)

        XCTAssertEqual(parkedWindows.placement(of: 100), .active)
        XCTAssertEqual(parkedWindows.placement(of: 200), .active)
        XCTAssertEqual(quitCount, 1)
    }

    func testRestartLeavesTheDeskWhereItStands() {
        let win1 = create(StubWindow(id: 100))
        create(StubWindow(id: 200))
        moveFocusedWindow(win1, to: 2)

        engine.handle(.restart)

        XCTAssertEqual(parkedWindows.placement(of: 100), .parked)
        XCTAssertEqual(parkedWindows.placement(of: 200), .active)
        XCTAssertEqual(restartCount, 1)
    }

    func testHandleActionSwitchesWorkspace() {
        engine.handle(Action.switchToWorkspace(2))

        XCTAssertEqual(workspaces.current, 2)
    }

    func testHandleActionMovesFocusedWindowToWorkspace() {
        focused = create(StubWindow(id: 100))

        engine.handle(Action.moveWindowToWorkspace(2))

        XCTAssertEqual(workspaces.workspace(for: 100), 2)
    }

    func testWindowEventsAreIgnoredWhileTheScreenIsLocked() {
        let win = create(StubWindow(id: 100))
        engine.switchToWorkspace(2)
        screenIsLocked = true

        engine.handle(.destroyed(100))
        engine.handle(.minimized(100))
        engine.handle(.created(add(StubWindow(id: 200)).snapshot()))

        XCTAssertEqual(workspaces.allWindowIds, [100])
        XCTAssertEqual(parkedWindows.placement(of: win.id), .parked)
    }

    func testWindowEventsAreHandledOnceTheScreenIsUnlocked() {
        create(StubWindow(id: 100))
        screenIsLocked = true
        engine.handle(.destroyed(100))
        screenIsLocked = false

        engine.handle(.destroyed(100))

        XCTAssertEqual(workspaces.allWindowIds, [])
    }

    // A window is dropped for reasons that do not mean it is gone: a stale registry, a
    // sweep that misread it. Forgetting it while it sits at the hidden edge leaves it
    // there with nobody left to bring it back.
    func testDroppingAParkedWindowHandsItBackToTheDesktop() {
        let parked = create(StubWindow(id: 100))
        let onDesk = create(StubWindow(id: 200))
        moveFocusedWindow(parked, to: 2)
        focused = onDesk
        desktop.clearPlaceCalls()

        engine.handle(.destroyed(100))

        XCTAssertEqual(desktop.placeCalls.map(\.windowId), [100])
        XCTAssertEqual(desktop.placeCalls.map(\.placement), [.active])
        XCTAssertEqual(parkedWindows.placement(of: 100), .active)
    }

    func testDroppingAWindowOnTheDesktopMovesNothing() {
        create(StubWindow(id: 100))
        desktop.clearPlaceCalls()

        engine.handle(.destroyed(100))

        XCTAssertTrue(desktop.placeCalls.isEmpty)
    }

    // Events are dropped while the screen is locked, so a window that appeared behind the
    // login window belongs to no workspace and no switch would ever move it.
    func testResyncAdoptsTheWindowsNoWorkspaceKnows() {
        let known = create(StubWindow(id: 100))
        let missed = add(StubWindow(id: 200))

        engine.resync(windows: [known.snapshot(), missed.snapshot()])

        XCTAssertEqual(workspaces.allWindowIds, [100, 200])
        XCTAssertEqual(workspaces.workspace(for: 200), 1)
    }

    func testResyncAdoptsIntoTheCurrentWorkspace() {
        let missed = add(StubWindow(id: 100))
        engine.switchToWorkspace(3)

        engine.resync(windows: [missed.snapshot()])

        XCTAssertEqual(workspaces.workspace(for: 100), 3)
    }

    func testResyncLeavesAWindowInTheWorkspaceItAlreadyBelongsTo() {
        let win = create(StubWindow(id: 100))
        moveFocusedWindow(win, to: 2)
        desktop.clearPlaceCalls()

        engine.resync(windows: [win.snapshot()])

        XCTAssertEqual(workspaces.workspace(for: 100), 2)
        XCTAssertTrue(desktop.placeCalls.isEmpty)
    }
}
