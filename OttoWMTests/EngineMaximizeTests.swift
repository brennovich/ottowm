import CoreGraphics
import XCTest

final class EngineMaximizeTests: EngineTestCase {
    private let frame = CGRect(x: 400, y: 300, width: 200, height: 200)

    @discardableResult
    private func focus(_ id: CGWindowID) -> StubWindow {
        let win = create(StubWindow(id: id, frame: frame))
        focused = win
        desktop.clearCalls()
        return win
    }

    func testATabOpenedWhileMaximizedKeepsTheFrameOnceTheOthersClose() {
        let win = focus(100)
        engine.handle(.toggleMaximize)
        let tab = create(StubWindow(id: 101, frame: frame, tabCount: 2))

        engine.handle(.destroyed(win.id))
        focused = tab
        desktop.clearCalls()
        engine.handle(.toggleMaximize)

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.maximize(restoring: frame)])
    }

    /// Parking and unparking report `.active`, which is what tells `RestoringFrames` the
    /// window left the filled frame. Only the reframe path feeds it, so a trip to another
    /// workspace and back does not.
    func testAWindowThatVisitedAnotherWorkspaceCanStillBePutBack() {
        let win = focus(100)
        engine.handle(.toggleMaximize)

        moveFocusedWindow(win, to: 2)
        engine.switchToWorkspace(2)
        focused = win
        desktop.clearCalls()

        engine.handle(.toggleMaximize)

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.maximize(restoring: frame)])
    }
}
