import CoreGraphics
import XCTest

final class EngineAdmissionTests: EngineTestCase {
    func testInvalidWindowsAreNeverAdmitted() {
        offScreenWindowIds = [500]
        let invalid = [
            add(StubWindow(id: 400, isFullScreen: true)),
            add(StubWindow(id: 500)),
        ]

        engine.start(windows: invalid.map { $0.snapshot() })
        for win in invalid {
            engine.handle(.created(win.snapshot()))
            engine.handle(.focused(win.snapshot()))
        }

        XCTAssertEqual(workspaces.allWindowIds, [])
    }

    func testCreatedWindowIsAssignedToCurrentWorkspace() {
        engine.switchToWorkspace(2)
        create(StubWindow(id: 100))

        XCTAssertEqual(workspaces.allWindowIds, [100])

        engine.switchToWorkspace(1)

        XCTAssertEqual(parkedWindows.placement(of: 100), .parked)
    }

    func testFocusedUnknownWindowIsAssignedToCurrentWorkspace() {
        engine.switchToWorkspace(2)
        let win = add(StubWindow(id: 100))

        engine.handle(.focused(win.snapshot()))

        XCTAssertEqual(workspaces.workspace(for: 100), 2)
        XCTAssertEqual(workspaces.current, 2)
    }

    func testWindowsCreatedOrFocusedOnAnotherNativeSpaceAreIgnored() {
        create(StubWindow(id: 100))
        offScreenWindowIds = [100]
        desktop.clearPlaceCalls()

        create(StubWindow(id: 200))
        let win = add(StubWindow(id: 300))
        focused = win
        engine.handle(.focused(win.snapshot()))

        XCTAssertEqual(workspaces.allWindowIds, [100])
        XCTAssertTrue(desktop.placeCalls.isEmpty)
        XCTAssertEqual(workspaces.current, 1)
    }

    func testWindowNotYetOnScreenIsAdoptedByARetry() {
        offScreenWindowIds = [100]
        create(StubWindow(id: 100))

        XCTAssertEqual(workspaces.allWindowIds, [])

        offScreenWindowIds = []
        runScheduledRetries()

        XCTAssertEqual(workspaces.workspace(for: 100), workspaces.current)
        XCTAssertEqual(parkedWindows.placement(of: 100), .active)
    }

    func testFocusedWindowNotYetOnScreenIsAdoptedByARetry() {
        offScreenWindowIds = [100]
        let win = add(StubWindow(id: 100))
        engine.handle(.focused(win.snapshot()))

        XCTAssertEqual(workspaces.allWindowIds, [])

        offScreenWindowIds = []
        runScheduledRetries()

        XCTAssertEqual(workspaces.workspace(for: 100), workspaces.current)
    }

    func testRetryStopsWhenTheWindowStaysOffScreen() {
        offScreenWindowIds = [100]
        create(StubWindow(id: 100))

        XCTAssertEqual(runScheduledRetries(), [0.1, 0.2, 0.4, 0.8])
        XCTAssertTrue(scheduledRetries.isEmpty)
        XCTAssertEqual(workspaces.allWindowIds, [])
    }

    func testRetryLeavesAWindowAssignedMeanwhileWhereItIs() {
        offScreenWindowIds = [100]
        let win = create(StubWindow(id: 100))
        offScreenWindowIds = []
        moveFocusedWindow(win, to: 2)

        runScheduledRetries()

        XCTAssertEqual(workspaces.workspace(for: 100), 2)
    }
}
