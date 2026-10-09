import CoreGraphics
import XCTest

final class WindowPlacementRelocateTests: EngineTestCase {
    private let dockMoved = Display(
        id: Display.standard.id,
        fullFrame: Display.standard.fullFrame,
        visibleFrame: CGRect(x: 0, y: 38, width: 1792, height: 1000)
    )
    private lazy var change = DisplayChange(from: .standard, to: dockMoved)

    func testRelocateParksOnlyTheParkedWindowsAgainFromTheirFittedFrames() {
        let active = add(StubWindow(id: 100))
        let parked = add(StubWindow(id: 200, frame: CGRect(x: 300, y: 200, width: 640, height: 480)))
        placement.assign(active.snapshot(), to: 1)
        placement.assign(parked.snapshot(), to: 2)
        desktop.clearCalls()

        placement.relocate(change)

        XCTAssertEqual(desktop.reframeCalls.map(\.windowId), [200])
        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.park(from: change.fit.frame(parked.frame))])
    }

    func testRelocateFitsTheFramesARestoreGoesBackTo() {
        let win = add(StubWindow(id: 100))
        let original = CGRect(x: 300, y: 200, width: 640, height: 480)
        placement.assign(win.snapshot(), to: 1)
        originalFrames.record([.filled(100, from: original)])

        placement.relocate(change)

        XCTAssertEqual(originalFrames.originalFrame(of: 100), change.fit.frame(original))
    }

    func testRelocateDropsAWindowTheDesktopReportsGone() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 2)
        windows[100] = nil

        placement.relocate(change)

        XCTAssertEqual(workspaces.allWindowIds, [])
    }
}
