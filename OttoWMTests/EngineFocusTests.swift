import CoreGraphics
import XCTest

final class EngineFocusTests: EngineTestCase {
    func testFocusedParkedWindowSwitchesToItsWorkspace() {
        let win = create(StubWindow(id: 700))
        engine.switchToWorkspace(2)

        XCTAssertEqual(parkedWindows.placement(of: 700), .parked)

        focused = win
        engine.handle(.focused(win.snapshot()))

        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(parkedWindows.placement(of: 700), .active)
    }

    func testStaleFocusEventForParkedWindowIsIgnored() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        focused = win1
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(parkedWindows.placement(of: 200), .parked)
    }

    func testFocusedParkedWindowDoesNotSwitchWhenCurrentWorkspaceWindowClosedBeforeItsDestroyedEvent() {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        offScreenWindowIds = [100]
        focused = win2
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(parkedWindows.placement(of: 200), .parked)
    }

    func testFocusedParkedWindowDoesNotSwitchWhenOneWindowOfTheCurrentWorkspaceClosed() {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)
        let survivor = create(StubWindow(id: 101))

        windows[100] = nil
        focused = win2
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(parkedWindows.placement(of: 200), .parked)
        XCTAssertEqual(workspaces.allWindowIds, [101, 200])
        XCTAssertEqual(survivor.focusCount, 1)
    }

    func testFocusedParkedWindowSwitchesWhenCurrentWorkspaceWindowIsOnlyMinimized() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        win1.isMinimized = true
        offScreenWindowIds = [100]
        focused = win2
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.current, 2)
        XCTAssertEqual(parkedWindows.placement(of: 200), .active)
    }

    func testDestroyedParkedWindowIsNoLongerParked() {
        let win = create(StubWindow(id: 200))
        moveFocusedWindow(win, to: 2)

        windows[200] = nil
        engine.handle(.destroyed(200))

        XCTAssertEqual(parkedWindows.placement(of: 200), .active)
    }

    func testDestroyedWindowThatWasNeverManagedDoesNotMoveTheFocus() {
        let win1 = create(StubWindow(id: 100))
        engine.handle(.focused(win1.snapshot()))

        engine.handle(.destroyed(900))

        XCTAssertEqual(win1.focusCount, 0)
    }

    func testDestroyedWindowRestoresFocusToPreviousWindow() {
        let win1 = create(StubWindow(id: 100))
        engine.handle(.focused(win1.snapshot()))
        create(StubWindow(id: 200))

        windows[200] = nil
        engine.handle(.destroyed(200))

        XCTAssertEqual(win1.focusCount, 1)
        XCTAssertEqual(workspaces.allWindowIds, [100])
    }
}
