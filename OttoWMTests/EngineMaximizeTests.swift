import CoreGraphics
import XCTest

final class EngineMaximizeTests: EngineTestCase {
    private let frame = CGRect(x: 400, y: 300, width: 200, height: 200)

    private func focus(_ id: CGWindowID) -> StubWindow {
        let win = create(StubWindow(id: id, frame: frame))
        focused = win
        desktop.clearCalls()
        return win
    }

    func testTheNextMaximizeHandsBackTheFrameTheFirstTookTheWindowFrom() {
        let win = focus(100)

        engine.handle(.toggleMaximize)
        engine.handle(.toggleMaximize)

        XCTAssertEqual(desktop.reframeCalls.map(\.windowId), [win.id, win.id])
        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.maximize(restoring: nil), .maximize(restoring: frame)])
    }

    func testClosingTheTabAMaximizeWentThroughLeavesItsSiblingsTheFrame() {
        focus(100)
        let tab = create(StubWindow(id: 101, frame: frame, tabCount: 2))
        focused = tab
        engine.handle(.toggleMaximize)

        engine.handle(.destroyed(tab.id))
        focused = windows[100]
        desktop.clearCalls()
        engine.handle(.toggleMaximize)

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.maximize(restoring: frame)])
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

    func testMovingAMaximizedWindowLeavesNothingToRestore() {
        focus(100)
        engine.handle(.toggleMaximize)

        engine.handle(.moveWindow(Step(direction: .east, points: 15)))
        desktop.clearCalls()
        engine.handle(.toggleMaximize)

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.maximize(restoring: nil)])
    }

    /// Parking and unparking report `.active`, which is what tells the maximize store the
    /// window left the filled frame. Only the reframe path feeds that store, so a trip to
    /// another workspace and back does not.
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

    func testDroppingAWindowForgetsTheFrameToRestore() {
        let win = focus(100)
        engine.handle(.toggleMaximize)

        engine.handle(.destroyed(win.id))

        XCTAssertNil(filledWindows.restoringFrame(of: win.id))
    }
}
