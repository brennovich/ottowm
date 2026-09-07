import CoreGraphics
import XCTest

final class EngineFillTests: EngineTestCase {
    private let frame = CGRect(x: 400, y: 300, width: 200, height: 200)

    private func focus(_ id: CGWindowID) -> StubWindow {
        let win = create(StubWindow(id: id, frame: frame))
        focused = win
        desktop.clearCalls()
        return win
    }

    func testTheFirstFillHasNothingToRestore() {
        let win = focus(100)

        engine.handle(.fill(.west))

        XCTAssertEqual(desktop.reframeCalls.map(\.windowId), [win.id])
        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.fill(.west, restoring: nil)])
    }

    func testTheNextFillHandsBackTheFrameTheWindowCameFrom() {
        focus(100)
        engine.handle(.fill(.west))
        desktop.clearCalls()

        engine.handle(.fill(.west))

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.fill(.west, restoring: frame)])
    }

    func testAFillAndAMaximizeGoBackToTheSameFrame() {
        focus(100)
        engine.handle(.toggleMaximize)
        desktop.clearCalls()

        engine.handle(.fill(.east))

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.fill(.east, restoring: frame)])
    }

    func testATabOpenedWhileFilledGoesBackToTheFrameItsWindowCameFrom() {
        focus(100)
        engine.handle(.fill(.north))

        let tab = create(StubWindow(id: 101, frame: frame, tabCount: 2))
        focused = tab
        desktop.clearCalls()
        engine.handle(.fill(.north))

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.fill(.north, restoring: frame)])
    }

    func testMovingAFilledWindowLeavesNothingToRestore() {
        focus(100)
        engine.handle(.fill(.south))

        engine.handle(.moveWindow(Step(direction: .east, points: 15)))
        desktop.clearCalls()
        engine.handle(.fill(.south))

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.fill(.south, restoring: nil)])
    }
}
