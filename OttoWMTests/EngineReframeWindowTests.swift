import CoreGraphics
import XCTest

final class EngineReframeWindowTests: EngineTestCase {
    private let frame = CGRect(x: 400, y: 300, width: 200, height: 200)
    private let step = Step(direction: .east, points: 15)

    func testForwardsTheChangeToTheDesktop() {
        let win = create(StubWindow(id: 100, frame: frame))
        focused = win

        engine.reframeFocusedWindow(.step(step))

        XCTAssertEqual(desktop.reframeCalls.map(\.windowId), [win.id])
        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.step(step)])
    }

    func testUnassignedFocusedWindowIsEnrolledFirst() {
        let win = add(StubWindow(id: 900, frame: frame))
        focused = win

        engine.reframeFocusedWindow(.step(step))

        XCTAssertEqual(workspaces.workspace(for: 900), 1)
        XCTAssertEqual(desktop.reframeCalls.map(\.windowId), [900])
    }

    func testNothingHappensWhenNoWindowOfTheCurrentWorkspaceIsFocused() {
        focused = nil

        engine.reframeFocusedWindow(.step(step))

        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testParkedWindowOfTheCurrentWorkspaceIsLeftAlone() {
        let win = create(StubWindow(id: 100, frame: frame))
        focused = win
        parkedWindows.park(win.id, owing: frame)

        engine.reframeFocusedWindow(.step(step))

        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testWindowThatNoLongerExistsIsDropped() {
        let win = create(StubWindow(id: 100, frame: frame))
        focused = win
        windows[win.id] = nil

        engine.reframeFocusedWindow(.step(step))

        XCTAssertNil(workspaces.workspace(for: win.id))
    }
}
