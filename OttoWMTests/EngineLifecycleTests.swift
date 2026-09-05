import CoreGraphics
import XCTest

final class EngineLifecycleTests: EngineTestCase {
    func testStartRecoversAndSeedsWindowsIntoWorkspaceOne() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))

        engine.start(windows: [win1.snapshot(), win2.snapshot()])

        XCTAssertEqual(desktop.recoveredWindowIds, [100, 200])
        XCTAssertEqual(workspaces.allWindowIds, [100, 200])
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

    func testHandleDispatchesEachAction() {
        let frame = CGRect(x: 400, y: 300, width: 200, height: 200)
        let win = create(StubWindow(id: 100, frame: frame))
        let neighbor = create(StubWindow(id: 200, frame: CGRect(x: 700, y: 300, width: 200, height: 200)))
        focused = win

        engine.handle(.focus(.east))

        XCTAssertEqual(neighbor.focusCount, 1)

        let step = Step(direction: .south, points: 40)
        engine.handle(.moveWindow(step))
        engine.handle(.centerWindow)

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.step(step), .center])

        engine.handle(.moveWindowToWorkspace(2))

        XCTAssertEqual(workspaces.workspace(for: 100), 2)

        engine.handle(.switchToWorkspace(2))

        XCTAssertEqual(workspaces.current, 2)
    }

    func testWindowEventsAreIgnoredOnlyWhileTheScreenIsLocked() {
        let win = create(StubWindow(id: 100))
        engine.switchToWorkspace(2)
        screenIsLocked = true

        engine.handle(.destroyed(100))
        engine.handle(.minimized(100))
        engine.handle(.created(add(StubWindow(id: 200)).snapshot()))

        XCTAssertEqual(workspaces.allWindowIds, [100])
        XCTAssertEqual(parkedWindows.placement(of: win.id), .parked)

        screenIsLocked = false
        engine.handle(.destroyed(100))

        XCTAssertEqual(workspaces.allWindowIds, [])
    }

    // Events are dropped while the screen is locked, so a window that appeared behind the
    // login window belongs to no workspace and no switch would ever move it.
    func testResyncEnrollsOnlyTheWindowsNoWorkspaceKnowsIntoTheCurrentWorkspace() {
        let known = create(StubWindow(id: 100))
        moveFocusedWindow(known, to: 2)
        let missed = add(StubWindow(id: 200))
        engine.switchToWorkspace(3)
        desktop.clearPlaceCalls()

        engine.resync(windows: [known.snapshot(), missed.snapshot()])

        XCTAssertEqual(workspaces.workspace(for: 100), 2)
        XCTAssertEqual(workspaces.workspace(for: 200), 3)
        XCTAssertEqual(desktop.placeCalls.map(\.windowId), [200])
    }
}
