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

    func testStopBringsEveryParkedWindowBack() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win1, to: 2)
        moveFocusedWindow(win2, to: 3)

        engine.stop()

        XCTAssertEqual(desktop.placement(of: 100), .active)
        XCTAssertEqual(desktop.placement(of: 200), .active)
    }

    func testQuitBringsEveryParkedWindowBackBeforeLeaving() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win1, to: 2)
        moveFocusedWindow(win2, to: 3)

        engine.handle(.quit)

        XCTAssertEqual(desktop.placement(of: 100), .active)
        XCTAssertEqual(desktop.placement(of: 200), .active)
        XCTAssertEqual(quitCount, 1)
    }

    func testRestartLeavesTheDeskWhereItStands() {
        let win1 = create(StubWindow(id: 100))
        create(StubWindow(id: 200))
        moveFocusedWindow(win1, to: 2)

        engine.handle(.restart)

        XCTAssertEqual(desktop.placement(of: 100), .storage)
        XCTAssertEqual(desktop.placement(of: 200), .active)
        XCTAssertEqual(restartCount, 1)
    }

    func testHandleActionSwitchesWorkspace() {
        create(StubWindow(id: 100))

        engine.handle(Action.switchToWorkspace(2))

        XCTAssertEqual(workspaces.current, 2)
        XCTAssertEqual(desktop.placement(of: 100), .storage)
    }

    func testHandleActionMovesFocusedWindowToWorkspace() {
        let win = create(StubWindow(id: 100))
        focused = win

        engine.handle(Action.moveWindowToWorkspace(2))

        XCTAssertEqual(desktop.placement(of: 100), .storage)
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
}
