import CoreGraphics
import XCTest

final class EngineFocusTests: EngineTestCase {
    func testManualNavigationToHiddenWindowSwitchesToItsWorkspace() {
        let win = add(StubWindow(id: 700))
        engine.start(windows: [win.snapshot()])
        engine.switchToWorkspace(2)

        XCTAssertEqual(desktop.placement(of: 700), .storage)

        focused = win
        desktop.manualNavigationCallback?(700)

        XCTAssertEqual(workspaces.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 700), .active)
    }

    func testFocusedStorageWindowSwitchesToItsWorkspace() {
        let win = create(StubWindow(id: 700))
        engine.switchToWorkspace(2)

        XCTAssertEqual(desktop.placement(of: 700), .storage)

        focused = win
        engine.handle(.focused(win.snapshot()))

        XCTAssertEqual(workspaces.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 700), .active)
    }

    func testStaleFocusEventForStorageWindowIsIgnored() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        focused = win1
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 200), .storage)
    }

    func testFocusEchoFromTheWorkspaceLeftDoesNotBounceBack() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)
        focused = win1

        engine.switchToWorkspace(2)
        engine.handle(.focused(win1.snapshot()))

        XCTAssertEqual(workspaces.currentWorkspace, 2)
        XCTAssertEqual(desktop.placement(of: 100), .storage)
        XCTAssertEqual(desktop.placement(of: 200), .active)
    }

    func testFocusedStorageWindowDoesNotSwitchWhileCurrentWorkspaceIsClosing() {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        windows[100] = nil
        focused = win2
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 200), .storage)
    }

    func testFocusedStorageWindowDoesNotSwitchWhenCurrentWorkspaceWindowClosedBeforeItsDestroyedEvent() {
        create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        offScreenWindowIds = [100]
        focused = win2
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.currentWorkspace, 1)
        XCTAssertEqual(desktop.placement(of: 200), .storage)
    }

    func testFocusedStorageWindowSwitchesWhenCurrentWorkspaceWindowIsOnlyMinimized() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))
        moveFocusedWindow(win2, to: 2)

        win1.isMinimized = true
        offScreenWindowIds = [100]
        focused = win2
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.currentWorkspace, 2)
        XCTAssertEqual(desktop.placement(of: 200), .active)
    }

    func testDestroyedWindowRestoresFocusToPreviousWindow() {
        let win1 = create(StubWindow(id: 100))
        engine.handle(.focused(win1.snapshot()))
        create(StubWindow(id: 200))

        windows[200] = nil
        engine.handle(.destroyed(200))

        XCTAssertEqual(win1.focusCount, 1)
        XCTAssertEqual(desktop.forgottenWindowIds, [200])
        XCTAssertEqual(workspaces.allWindowIds, [100])
    }
}
