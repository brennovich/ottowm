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

    func testNativeSpaceChangeFollowsTheWindowBackFromFullScreen() {
        engine.start(windows: [])
        let win2 = sendWindowFullScreenAndLeave()

        win2.isFullScreen = false
        offScreenWindowIds = []
        desktop.nativeSpaceChangeCallback?()

        XCTAssertEqual(workspaces.current, 1)
    }

    func testWindowBackFromFullScreenIsFollowedWhenAnotherWindowEventArrives() {
        let win2 = sendWindowFullScreenAndLeave()

        win2.isFullScreen = false
        offScreenWindowIds = []
        focused = nil
        engine.handle(.destroyed(999))

        XCTAssertEqual(workspaces.current, 1)
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
