import CoreGraphics
import XCTest

final class EngineMinimizeTests: EngineTestCase {
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

        XCTAssertEqual(parkedWindows.placement(of: 100), .parked)
    }
}
