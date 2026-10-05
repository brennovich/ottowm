import CoreGraphics
import XCTest

final class WindowPlacementReleaseTests: EngineTestCase {
    func testReleaseTakesTheWholeTabGroup() {
        placement.assign(add(StubWindow(id: 300, appName: "Terminal", frame: tabFrame, tabCount: 2)).snapshot(), to: 1)
        placement.assign(add(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2)).snapshot(), to: 1)

        placement.release(301)

        XCTAssertEqual(workspaces.allWindowIds, [])
    }

    func testReleaseDropsTheFrameAMaximizeGoesBackTo() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 1)
        placement.reframe(win.snapshot()) { .maximize(restoring: $0) }

        placement.release(100)

        XCTAssertNil(originalFrames.originalFrame(of: 100))
    }
}
