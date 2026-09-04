import CoreGraphics
import XCTest

final class EngineMoveWindowDirectionTests: EngineTestCase {
    private let frame = CGRect(x: 400, y: 300, width: 200, height: 200)
    private let step = Step(direction: .east, points: 15)

    func testMovesTheFocusedWindow() {
        let win = create(StubWindow(id: 100, frame: frame))
        focused = win

        engine.moveFocusedWindow(step)

        XCTAssertEqual(win.frame, frame.offsetBy(dx: 15, dy: 0))
        XCTAssertEqual(desktop.moveCalls.map(\.windowId), [win.id])
    }

    func testUnassignedFocusedWindowIsEnrolledAndMoved() {
        let win = add(StubWindow(id: 900, frame: frame))
        focused = win

        engine.moveFocusedWindow(step)

        XCTAssertEqual(workspaces.workspace(for: 900), 1)
        XCTAssertEqual(win.frame, frame.offsetBy(dx: 15, dy: 0))
    }

    func testNothingMovesWhenNoWindowOfTheCurrentWorkspaceIsFocused() {
        focused = nil

        engine.moveFocusedWindow(step)

        XCTAssertTrue(desktop.moveCalls.isEmpty)
    }

    func testParkedWindowOfTheCurrentWorkspaceMovesNothing() {
        let win = create(StubWindow(id: 100, frame: frame))
        focused = win
        parkedWindows.park(win.id, owing: frame)

        engine.moveFocusedWindow(step)

        XCTAssertTrue(desktop.moveCalls.isEmpty)
        XCTAssertEqual(win.frame, frame)
    }

    func testWindowThatNoLongerExistsIsDropped() {
        let win = create(StubWindow(id: 100, frame: frame))
        focused = win
        windows[win.id] = nil

        engine.moveFocusedWindow(step)

        XCTAssertNil(workspaces.workspace(for: win.id))
    }
}
