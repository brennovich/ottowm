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
        XCTAssertEqual(win1.focusCount, 1)
    }

    func testWindowBackFromFullScreenReturnsToTheWorkspaceItLeftAndTakesTheDesktopThere() {
        let win2 = sendWindowFullScreenAndLeave()

        win2.isFullScreen = false
        offScreenWindowIds = []
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.workspace(for: 200), 1)
        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(parkedWindows.placement(of: 200), .active)
    }

    func testNativeSpaceChangeFollowsTheWindowBackFromFullScreen() {
        engine.start(windows: [])
        let win2 = sendWindowFullScreenAndLeave()

        win2.isFullScreen = false
        offScreenWindowIds = []
        desktop.nativeSpaceChangeCallback?()

        XCTAssertEqual(workspaces.workspace(for: 200), 1)
        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(parkedWindows.placement(of: 200), .active)
    }

    func testWindowBackFromFullScreenIsFollowedWhenAnotherWindowEventArrives() {
        let win2 = sendWindowFullScreenAndLeave()

        win2.isFullScreen = false
        offScreenWindowIds = []
        focused = nil
        engine.handle(.destroyed(999))

        XCTAssertEqual(workspaces.workspace(for: 200), 1)
        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(parkedWindows.placement(of: 200), .active)
        XCTAssertEqual(parkedWindows.placement(of: 100), .active)
        XCTAssertEqual(win2.focusCount, 1)
    }

    func testWindowStillLeavingFullScreenOnTheSpaceChangeIsFollowedOnARetry() {
        engine.start(windows: [])
        let win2 = sendWindowFullScreenAndLeave()

        desktop.nativeSpaceChangeCallback?()

        XCTAssertEqual(workspaces.current, 2)

        win2.isFullScreen = false
        offScreenWindowIds = []
        runScheduledRetries()

        XCTAssertEqual(workspaces.workspace(for: 200), 1)
        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(parkedWindows.placement(of: 200), .active)
    }

    func testTheRetriesForAWindowLeavingFullScreenStop() {
        engine.start(windows: [])
        _ = sendWindowFullScreenAndLeave()

        desktop.nativeSpaceChangeCallback?()

        XCTAssertEqual(runScheduledRetries(), [0.1, 0.2, 0.4, 0.8, 1.6])
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
