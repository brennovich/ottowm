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

    func testWindowOutsideTheCurrentWorkspaceMovesNothing() {
        let unmanaged = add(StubWindow(id: 900, frame: frame))
        let elsewhere = create(StubWindow(id: 200, frame: frame))
        moveFocusedWindow(elsewhere, to: 2)

        for reference in [nil, unmanaged, elsewhere] {
            focused = reference

            engine.moveFocusedWindow(step)

            XCTAssertTrue(desktop.moveCalls.isEmpty)
        }
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
        desktop.missingWindowIds = [win.id]

        engine.moveFocusedWindow(step)

        XCTAssertNil(workspaces.workspace(for: win.id))
    }

    func testHandleDispatchesTheMoveWindowAction() {
        let win = create(StubWindow(id: 100, frame: frame))
        focused = win

        engine.handle(.moveWindow(Step(direction: .south, points: 40)))

        XCTAssertEqual(win.frame, frame.offsetBy(dx: 0, dy: 40))
    }
}
