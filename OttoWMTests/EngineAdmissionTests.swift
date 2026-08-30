import CoreGraphics
import XCTest

final class EngineAdmissionTests: EngineTestCase {
    func testInvalidWindowsAreNeverAdmitted() {
        offScreenWindowIds = [500]
        let invalid = [
            add(StubWindow(id: 0)),
            add(StubWindow(id: 300, isStandard: false, hasMinimizeButton: false)),
            add(StubWindow(id: 400, isFullScreen: true)),
            add(StubWindow(id: 500)),
            add(StubWindow(id: 600, isMinimized: true)),
        ]

        engine.start(windows: invalid.map { $0.snapshot() })
        for win in invalid {
            engine.handle(.created(win.snapshot()))
            engine.handle(.focused(win.snapshot()))
        }

        XCTAssertEqual(workspaces.allWindowIds, [])
    }

    func testAWindowThatIsNotStandardButKeepsItsTitleBarButtonsIsAdmitted() {
        let win = add(StubWindow(id: 100, isStandard: false))

        engine.handle(.created(win.snapshot()))

        XCTAssertEqual(workspaces.allWindowIds, [100])
    }

    func testCreatedWindowIsAssignedToCurrentWorkspace() {
        engine.switchToWorkspace(2)
        create(StubWindow(id: 100))

        XCTAssertEqual(workspaces.allWindowIds, [100])

        engine.switchToWorkspace(1)

        XCTAssertEqual(parkedWindows.placement(of: 100), .storage)
    }

    func testFocusedUnknownWindowIsAssignedToCurrentWorkspace() {
        let win = add(StubWindow(id: 100))

        engine.handle(.focused(win.snapshot()))

        XCTAssertEqual(workspaces.allWindowIds, [100])
    }

    func testWindowCreatedOnAnotherNativeSpaceIsIgnored() {
        create(StubWindow(id: 100))
        offScreenWindowIds = [100]
        desktop.clearPlaceCalls()

        create(StubWindow(id: 200))

        XCTAssertEqual(workspaces.allWindowIds, [100])
        XCTAssertTrue(desktop.placeCalls.isEmpty)
    }

    func testWindowFocusedOnAnotherNativeSpaceIsNotAdopted() {
        create(StubWindow(id: 100))
        offScreenWindowIds = [100]
        let win = add(StubWindow(id: 200))

        focused = win
        engine.handle(.focused(win.snapshot()))

        XCTAssertEqual(workspaces.allWindowIds, [100])
        XCTAssertEqual(workspaces.current, 1)
    }
}
