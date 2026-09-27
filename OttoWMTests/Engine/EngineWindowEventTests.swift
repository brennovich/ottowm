import CoreGraphics
import XCTest

final class EngineWindowEventTests: EngineTestCase {
    func testCreatedWindowIsAssignedToCurrentWorkspace() {
        engine.switchToWorkspace(2)
        create(StubWindow(id: 100))

        XCTAssertEqual(workspaces.workspace(for: 100), 2)
    }

    func testFocusedParkedWindowSwitchesToItsWorkspace() {
        let win = create(StubWindow(id: 700))
        engine.switchToWorkspace(2)

        focused = win
        engine.handle(.focused(win.snapshot()))

        XCTAssertEqual(workspaces.current, 1)
    }

    func testAFocusEventRefreshesWhereAKnownWindowStands() {
        let win = create(StubWindow(id: 100))
        let moved = CGRect(x: 300, y: 200, width: 640, height: 480)
        win.moveTo(moved)

        engine.handle(.focused(win.snapshot()))

        XCTAssertEqual(layouts.frame(of: 100, on: Display.standard.id), moved)
    }

    func testDestroyedWindowRestoresFocusToPreviousWindow() {
        let win1 = create(StubWindow(id: 100))
        engine.handle(.focused(win1.snapshot()))
        create(StubWindow(id: 200))

        windows[200] = nil
        engine.handle(.destroyed(200))

        XCTAssertEqual(win1.focusCount, 1)
    }

    func testMinimizedWindowIsDroppedFromItsWorkspace() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))

        win2.isMinimized = true
        engine.handle(.minimized(200))

        XCTAssertEqual(workspaces.allWindowIds, [100])
        XCTAssertEqual(win1.focusCount, 1)
    }

    func testMinimizedTabGroupHandsFocusToAWindowStillOnScreen() {
        let (tab1, tab2, other) = createFocusedTabPair()

        tab1.isMinimized = true
        tab2.isMinimized = true
        engine.handle(.minimized(301))

        XCTAssertEqual(workspaces.allWindowIds, [100])
        XCTAssertEqual(other.focusCount, 1)
        XCTAssertEqual(tab1.focusCount, 0)
    }

    func testUnminimizedWindowIsRecoveredAndJoinsTheCurrentWorkspace() {
        let win = create(StubWindow(id: 100))
        moveFocusedWindow(win, to: 2)
        engine.switchToWorkspace(2)
        win.isMinimized = true
        engine.handle(.minimized(100))
        engine.switchToWorkspace(1)

        win.isMinimized = false
        engine.handle(.unminimized(win.snapshot()))

        XCTAssertEqual(desktop.recoveredWindowIds, [100])
        XCTAssertEqual(workspaces.allWindowIds, [100])

        engine.switchToWorkspace(2)

        XCTAssertTrue(parkedWindows.isParked(100))
    }
}
