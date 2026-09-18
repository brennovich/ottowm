import CoreGraphics
import XCTest

final class WindowPlacementRelocateTests: EngineTestCase {
    func testRelocateFitsAnActiveWindowFromTheDisplayLeftIntoTheOneEntered() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 1)
        desktop.clearCalls()
        desktop.display = .external
        let fitted = DisplayChange(from: .standard, to: .external).fit.frame(win.frame)

        placement.relocate(DisplayChange(from: .standard, to: .external))

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.unpark(fitted)])
        XCTAssertEqual(layouts.frame(of: 100, on: Display.external.id), fitted)
    }

    func testRelocatePrefersTheFrameRememberedOnTheDisplayEntered() {
        let win = add(StubWindow(id: 100))
        let remembered = CGRect(x: 1000, y: 500, width: 1200, height: 800)
        placement.assign(win.snapshot(), to: 1)
        desktop.clearCalls()
        desktop.display = .external
        layouts.record(remembered, of: 100, on: Display.external.id)

        placement.relocate(DisplayChange(from: .standard, to: .external))

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.unpark(remembered)])
    }

    func testRelocateParksAParkedWindowAgainFromItsFittedFrame() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 2)
        desktop.clearCalls()
        desktop.display = .external
        let fitted = DisplayChange(from: .standard, to: .external).fit.frame(win.frame)

        placement.relocate(DisplayChange(from: .standard, to: .external))

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.park(from: fitted)])
    }

    func testRelocateOnTheSameDisplayMovesOnlyTheParkedWindows() {
        let active = add(StubWindow(id: 100))
        let parked = add(StubWindow(id: 200, frame: CGRect(x: 300, y: 200, width: 640, height: 480)))
        placement.assign(active.snapshot(), to: 1)
        placement.assign(parked.snapshot(), to: 2)
        desktop.clearCalls()
        let dockMoved = Display(
            id: Display.standard.id,
            fullFrame: Display.standard.fullFrame,
            visibleFrame: CGRect(x: 0, y: 38, width: 1792, height: 1000)
        )
        let fitted = DisplayChange(from: .standard, to: dockMoved).fit.frame(parked.frame)

        placement.relocate(DisplayChange(from: .standard, to: dockMoved))

        XCTAssertEqual(desktop.reframeCalls.map(\.windowId), [200])
        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.park(from: fitted)])
    }

    func testRelocateFitsTheFramesARestoreGoesBackTo() {
        let win = add(StubWindow(id: 100))
        let original = CGRect(x: 300, y: 200, width: 640, height: 480)
        placement.assign(win.snapshot(), to: 1)
        originalFrames.record([.filled(100, from: original)])
        let fit = DisplayChange(from: .standard, to: .external).fit

        placement.relocate(DisplayChange(from: .standard, to: .external))

        XCTAssertEqual(originalFrames.originalFrame(of: 100), fit.frame(original))
    }

    func testRelocateDropsAWindowTheDesktopReportsGone() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 1)
        windows[100] = nil

        placement.relocate(DisplayChange(from: .standard, to: .external))

        XCTAssertEqual(workspaces.allWindowIds, [])
    }
}
