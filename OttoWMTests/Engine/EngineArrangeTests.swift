import CoreGraphics
import XCTest

final class EngineArrangeTests: EngineTestCase {
    private var slots: [CGRect] {
        Tall(windowIds: [100, 200]).slots(within: desktop.workArea.filled, gap: desktop.workArea.spacing)
    }

    private func arrangeTwo() -> (main: StubWindow, stack: StubWindow) {
        let main = create(StubWindow(id: 100, frame: CGRect(x: 0, y: 100, width: 300, height: 300)))
        let stack = create(StubWindow(id: 200, frame: CGRect(x: 0, y: 500, width: 300, height: 300)))
        focused = main
        engine.handle(.arrange(.tall))
        desktop.clearCalls()
        return (main, stack)
    }

    func testArrangeArrangesTheWorkspaceAroundTheFocusedWindow() {
        let main = create(StubWindow(id: 100))
        focused = main
        desktop.clearCalls()

        engine.handle(.arrange(.tall))

        XCTAssertEqual(desktop.reframeCalls, [FrameRequest(windowId: 100, change: .arrange(into: desktop.workArea.filled))])
    }

    func testArrangeNeedsAFocusedWindowOnScreen() {
        focused = nil
        engine.handle(.arrange(.tall))

        let parked = create(StubWindow(id: 100))
        parkedWindows.park(parked.id, from: parked.frame)
        focused = parked
        desktop.clearCalls()
        engine.handle(.arrange(.tall))

        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testMoveWindowSwapsTheWindowsOfAnIntactArrangement() {
        let (_, stack) = arrangeTwo()
        focused = stack

        engine.handle(.moveWindow(.west))

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.arrange(into: slots[0]), .arrange(into: slots[1])])
    }

    func testResizeResizesAnIntactArrangement() {
        _ = arrangeTwo()

        engine.handle(.resize(.wider))

        XCTAssertEqual(desktop.reframeCalls.map(\.windowId), [100, 200])
        XCTAssertTrue(desktop.reframeCalls.allSatisfy { if case .arrange = $0.change { true } else { false } })
    }

    func testMaximizeReturnsAWindowOfAnIntactArrangementToItsSlot() {
        let (_, stack) = arrangeTwo()
        focused = stack
        stack.moveTo(desktop.workArea.filled)
        desktop.maximizedFrame = desktop.workArea.filled

        engine.handle(.maximize)

        XCTAssertEqual(desktop.reframeCalls, [FrameRequest(windowId: 200, change: .arrange(into: slots[1]))])
    }

    func testArrangeForgetsWhatItLearnedOfADestroyedWindow() {
        let main = create(StubWindow(id: 100, frame: CGRect(x: 0, y: 100, width: 300, height: 300)))
        let wide = create(StubWindow(id: 200, frame: CGRect(x: 0, y: 500, width: 300, height: 300)))
        let comeback = StubWindow(id: wide.id, frame: wide.frame)
        wide.minimumSize = CGSize(width: 1200, height: 0)
        focused = main
        engine.handle(.arrange(.tall))
        engine.handle(.destroyed(wide.id))
        create(comeback)
        desktop.clearCalls()

        engine.handle(.arrange(.tall))

        XCTAssertEqual(desktop.reframeCalls.map(\.change), slots.map { .arrange(into: $0) })
    }
}
