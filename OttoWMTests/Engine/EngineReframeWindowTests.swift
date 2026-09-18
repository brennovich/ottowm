import CoreGraphics
import XCTest

final class EngineReframeWindowTests: EngineTestCase {
    private let frame = CGRect(x: 400, y: 300, width: 200, height: 200)

    func testUnassignedFocusedWindowIsEnrolledFirst() {
        let win = add(StubWindow(id: 900, frame: frame))
        focused = win

        engine.handle(.moveWindow(.east))

        XCTAssertEqual(workspaces.workspace(for: 900), 1)
        XCTAssertEqual(desktop.reframeCalls.map(\.windowId), [900, 900])
        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.unpark(nil), .move(.east)])
    }

    func testNothingHappensWhenNoWindowOfTheCurrentWorkspaceIsFocused() {
        focused = nil

        engine.handle(.moveWindow(.east))

        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testAMaximizedWindowIsNeitherMovedNorResized() {
        focused = create(StubWindow(id: 100, frame: frame))
        desktop.maximizedFrame = frame
        desktop.clearCalls()

        for action in [Action.moveWindow(.east), .resize(.wider)] {
            engine.handle(action)
        }

        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testParkedWindowOfTheCurrentWorkspaceIsLeftAlone() {
        let win = create(StubWindow(id: 100, frame: frame))
        focused = win
        parkedWindows.park(win.id, from: frame)
        desktop.clearCalls()

        engine.handle(.moveWindow(.east))

        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }
}
