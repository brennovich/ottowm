import CoreGraphics
import XCTest

final class EngineMoveWindowTests: EngineTestCase {
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
        XCTAssertEqual(parkedWindows.placement(of: 100), .active)
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

        XCTAssertEqual(parkedWindows.placement(of: 100), .storage)

        engine.moveFocusedWindow(toWorkspace: 1)

        XCTAssertEqual(parkedWindows.placement(of: 100), .active)
    }
}
