import CoreGraphics
import XCTest

final class FullScreenReturnsTests: EngineTestCase {
    func testFollowTakesAWindowBackFromFullScreenToItsWorkspaceAndRestoresTheFocus() {
        let (win1, win2) = sendWindowFullScreenAndLeave()

        XCTAssertTrue(fullScreenReturns.follow())
        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(win2.focusCount, 1)
        XCTAssertEqual(win1.focusCount, 0)
    }

    func testFollowWithRetriesFollowsTheWindowOnceItReadsBack() {
        let (_, win2) = sendWindowFullScreenAndLeave()
        win2.isFullScreen = true

        fullScreenReturns.followWithRetries()

        XCTAssertEqual(workspaces.current, 2)

        win2.isFullScreen = false
        runScheduledRetries()

        XCTAssertEqual(workspaces.workspace(for: 200), 1)
        XCTAssertEqual(workspaces.current, 1)
        XCTAssertFalse(placement.isParked(200))
    }

    func testTheRetriesStopAfterTheLastDelay() {
        let (_, win2) = sendWindowFullScreenAndLeave()
        win2.isFullScreen = true

        fullScreenReturns.followWithRetries()

        XCTAssertEqual(runScheduledRetries(), [0.1, 0.2, 0.4, 0.8, 1.6])
        XCTAssertEqual(workspaces.current, 2)
    }

    func testNothingIsScheduledWithNoWindowOutInFullScreen() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 1)

        fullScreenReturns.followWithRetries()

        XCTAssertTrue(scheduledRetries.isEmpty)
    }

    private func sendWindowFullScreenAndLeave() -> (StubWindow, StubWindow) {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))
        placement.assign(win1.snapshot(), to: 1)
        placement.assign(win2.snapshot(), to: 1)
        placement.releaseToFullScreen(200, from: 1)
        placement.switchTo(2)
        return (win1, win2)
    }
}
