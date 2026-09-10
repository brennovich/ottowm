import CoreGraphics
import XCTest

final class EngineFocusTests: EngineTestCase {
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
}
