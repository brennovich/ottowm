import CoreGraphics
import XCTest

final class EngineFullScreenTests: EngineTestCase {
    func testSwitchDropsTheFocusedWindowThatWentFullScreen() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        engine.handle(.focused(win2.snapshot()))

        win2.isFullScreen = true
        focused = win2
        offScreenWindowIds = [100]
        engine.switchToWorkspace(1)

        XCTAssertEqual(workspaces.allWindowIds, [100])
        XCTAssertEqual(desktop.forgottenWindowIds, [200])
        XCTAssertEqual(win1.focusCount, 1)
    }

    func testWindowBackFromFullScreenReturnsToTheWorkspaceItLeftAndTakesTheDesktopThere() {
        let win2 = sendWindowFullScreenAndLeave()

        win2.isFullScreen = false
        offScreenWindowIds = []
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.workspace(for: 200), 1)
        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(desktop.placement(of: 200), .active)
    }

    func testWindowFoundBackFromFullScreenWhileRestoringFocusReturnsToTheWorkspaceItLeft() {
        let win2 = sendWindowFullScreenAndLeave()
        offScreenWindowIds = []
        create(StubWindow(id: 300))

        win2.isFullScreen = false
        windows[300] = nil
        engine.handle(.destroyed(300))

        XCTAssertEqual(workspaces.workspace(for: 200), 1)
        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(desktop.placement(of: 200), .active)
        XCTAssertEqual(desktop.placement(of: 100), .active)
    }

    func testMovingAWindowBackFromFullScreenOverridesTheWorkspaceItLeft() {
        let win2 = sendWindowFullScreenAndLeave()

        win2.isFullScreen = false
        offScreenWindowIds = []
        engine.moveFocusedWindow(toWorkspace: 3)
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.workspace(for: 200), 3)
        XCTAssertEqual(workspaces.current, 2)
    }

    func testWindowThatWasNeverManagedBeforeGoingFullScreenJoinsTheCurrentWorkspace() {
        create(StubWindow(id: 100))
        engine.switchToWorkspace(2)
        let win2 = add(StubWindow(id: 200, isFullScreen: true))
        focused = win2

        win2.isFullScreen = false
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.workspace(for: 200), 2)
        XCTAssertEqual(workspaces.current, 2)
    }

    private func sendWindowFullScreenAndLeave() -> StubWindow {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        win2.isFullScreen = true
        focused = win2
        offScreenWindowIds = [100]
        engine.switchToWorkspace(1)
        engine.switchToWorkspace(2)
        return win2
    }
}
