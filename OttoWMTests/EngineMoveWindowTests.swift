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

    func testMoveWindowToWorkspaceIgnoresAnInvalidTargetOrNoFocusedWindow() {
        focused = nil
        engine.moveFocusedWindow(toWorkspace: 2)

        focused = add(StubWindow(id: 100))
        engine.moveFocusedWindow(toWorkspace: 0)

        XCTAssertTrue(desktop.placeCalls.isEmpty)
        XCTAssertEqual(workspaces.allWindowIds, [])
    }
}
