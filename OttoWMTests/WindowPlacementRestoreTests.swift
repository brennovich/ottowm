import CoreGraphics
import XCTest

final class WindowPlacementRestoreTests: EngineTestCase {
    private let parkedFrom = CGRect(x: 300, y: 200, width: 640, height: 480)

    private func restore(_ windows: [StubWindow], from state: SavedState?) {
        placement.restore(windows.map { $0.snapshot() }, from: state)
    }

    func testRestoreParksOnlyTheWindowsSavedInAnotherWorkspace() {
        let active = add(StubWindow(id: 100))
        let other = add(StubWindow(id: 200, frame: parkedFrom))

        restore([active, other], from: savedState(current: 2, [(active, 1), (other, 2)]))

        XCTAssertEqual(workspaces.current, 2)
        XCTAssertEqual(workspaces.workspace(for: 100), 1)
        XCTAssertEqual(workspaces.workspace(for: 200), 2)
        XCTAssertEqual(placement.parked, [100: active.frame])
        XCTAssertEqual(desktop.reframeCalls.map(\.windowId), [100])
    }

    func testRestoreParksAWindowSavedAsParkedAgainFromItsSavedFrame() {
        let active = add(StubWindow(id: 100))
        let stuck = add(StubWindow(id: 200, frame: hiddenEdgeFrame(size: parkedFrom.size)))
        let state = savedState([(active, 1), (stuck, 2)], parked: [200: parkedFrom], original: [100: parkedFrom])

        restore([active, stuck], from: state)

        XCTAssertEqual(desktop.recoveredWindowIds, [100])
        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.park(from: parkedFrom)])
        XCTAssertEqual(placement.savedState, state)
    }

    func testRestoreTakesTheWindowsTheStateDoesNotHoldIntoTheSavedCurrentWorkspace() {
        let known = add(StubWindow(id: 100))
        let new = add(StubWindow(id: 300))

        restore([known, new], from: savedState(current: 2, [(known, 2)]))

        XCTAssertEqual(workspaces.windowIds(in: 2), [100, 300])
    }

    func testRestoreLeavesOutTheSavedWindowsAdmissionRefuses() {
        let minimized = add(StubWindow(id: 100, isMinimized: true))

        restore([minimized], from: savedState([(StubWindow(id: 100), 2)]))

        XCTAssertNil(workspaces.workspace(for: 100))
    }

    func testRestorePlacesTheWindowsSavedOnAnotherDisplayOnTheOneHeldNow() {
        let active = add(StubWindow(id: 100))
        let stuck = add(StubWindow(id: 200, frame: hiddenEdgeFrame(size: parkedFrom.size, on: .external)))
        let fitted = DisplayChange(from: .external, to: .standard).fit.frame(parkedFrom)

        restore([active, stuck], from: savedState([(active, 1), (stuck, 2)], parked: [200: parkedFrom], on: .external))

        XCTAssertEqual(placement.parked, [200: fitted])
    }

    func testRestoreWithoutAStateTakesEveryWindowIntoWorkspaceOne() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))

        restore([win1, win2], from: nil)

        XCTAssertEqual(desktop.recoveredWindowIds, [100, 200])
        XCTAssertEqual(workspaces.windowIds(in: 1), [100, 200])
    }
}
