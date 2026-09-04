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

    func testDestroyedWindowRestoresFocusToPreviousWindow() {
        let win1 = create(StubWindow(id: 100))
        engine.handle(.focused(win1.snapshot()))
        create(StubWindow(id: 200))

        windows[200] = nil
        engine.handle(.destroyed(200))

        XCTAssertEqual(win1.focusCount, 1)
    }
}
