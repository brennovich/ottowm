import CoreGraphics
import XCTest

final class WindowPlacementTests: EngineTestCase {
    func testOnlyAnAdmissibleWindowOnScreenIsAssigned() {
        offScreenWindowIds = [500]
        let offScreen = add(StubWindow(id: 500))
        let admissible = add(StubWindow(id: 600))

        XCTAssertNil(placement.assign(offScreen.snapshot(), to: 1))
        XCTAssertEqual(placement.assign(admissible.snapshot(), to: 1), 1)
        XCTAssertEqual(workspaces.allWindowIds, [600])
    }

    func testAssignReportsTheWorkspaceOfAKnownWindowAndLeavesItThere() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 2)
        desktop.clearCalls()

        XCTAssertEqual(placement.assign(win.snapshot(), to: 1), 2)
        XCTAssertEqual(workspaces.workspace(for: 100), 2)
        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testNothingIsAssignedWhileAnotherNativeSpaceIsInFront() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 1)
        offScreenWindowIds = [100]
        desktop.clearCalls()

        let other = add(StubWindow(id: 200))

        XCTAssertFalse(placement.isDesktopInFront)
        XCTAssertNil(placement.assign(other.snapshot(), to: 1))
        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testTheDesktopIsInFrontWhenTheFocusedWindowBelongsToAManagedTabGroup() {
        let tab1 = add(StubWindow(id: 300, appName: "Terminal", frame: tabFrame, tabCount: 2))
        placement.assign(tab1.snapshot(), to: 1)
        let tab2 = add(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))
        offScreenWindowIds = [300]

        focused = add(StubWindow(id: 100))

        XCTAssertFalse(placement.isDesktopInFront)

        focused = tab2

        XCTAssertTrue(placement.isDesktopInFront)
    }

    func testAssignPlacesAWindowByTheWorkspaceItsTabGroupHolds() {
        let tab1 = add(StubWindow(id: 300, appName: "Terminal", frame: tabFrame, tabCount: 2))
        placement.assign(tab1.snapshot(), to: 1)
        placement.switchTo(2)
        let tab2 = add(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))

        XCTAssertEqual(placement.assign(tab2.snapshot(), to: 2), 1)
        XCTAssertTrue(placement.isParked(301))
    }

    func testUnmanageHandsAParkedWindowBackToTheDesktop() {
        let parked = add(StubWindow(id: 100))
        let onDesk = add(StubWindow(id: 200))
        placement.assign(parked.snapshot(), to: 2)
        placement.assign(onDesk.snapshot(), to: 1)
        desktop.clearCalls()

        placement.unmanage(100, reason: "test")

        XCTAssertEqual(desktop.reframeCalls.map(\.windowId), [100])
        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.unpark(parked.frame)])
        XCTAssertFalse(placement.isParked(100))

        desktop.clearCalls()
        placement.unmanage(200, reason: "test")

        XCTAssertTrue(desktop.reframeCalls.isEmpty)
        XCTAssertEqual(workspaces.allWindowIds, [])
    }

    func testUnmanageForgetsTheParkedFrameOfAWindowTheDesktopReportsGone() {
        let win = add(StubWindow(id: 200))
        placement.assign(win.snapshot(), to: 2)

        windows[200] = nil
        placement.unmanage(200, reason: "test")

        XCTAssertFalse(placement.isParked(200))
    }

    func testUnmanageReportsTheFocusSettledForAWindowItNeverManaged() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 1)

        XCTAssertTrue(placement.unmanage(900, reason: "test"))
        XCTAssertFalse(placement.unmanage(100, reason: "test"))
    }

    func testSwitchToParksTheWindowsLeftAndActivatesTheTargetsInOneBatch() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))
        placement.assign(win1.snapshot(), to: 1)
        placement.assign(win2.snapshot(), to: 2)
        desktop.clearCalls()

        placement.switchTo(2)

        XCTAssertEqual(workspaces.current, 2)
        XCTAssertTrue(placement.isParked(100))
        XCTAssertFalse(placement.isParked(200))
        XCTAssertEqual(desktop.reframeBatches.map(Set.init), [[100, 200]])
    }

    func testSwitchToUnmanagesTheWindowsTheDesktopReportsGone() {
        let win1 = add(StubWindow(id: 100))
        let doomed = add(StubWindow(id: 300))
        placement.assign(win1.snapshot(), to: 1)
        placement.assign(doomed.snapshot(), to: 2)

        windows[300] = nil
        placement.switchTo(2)

        XCTAssertNil(workspaces.workspace(for: 300))
        XCTAssertFalse(placement.isParked(300))
    }

    func testSwitchToRecordsTheFocusOnTheManageableWindowFocusedWhenLeaving() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))
        placement.assign(win1.snapshot(), to: 1)
        placement.assign(win2.snapshot(), to: 1)

        focused = win1
        placement.switchTo(2)
        placement.switchTo(1)

        XCTAssertEqual(workspaces.nextWindowToFocus, 100)

        offScreenWindowIds = [200]
        focused = win2
        placement.switchTo(2)
        placement.switchTo(1)

        XCTAssertEqual(workspaces.nextWindowToFocus, 100)
    }

    func testMovePlacesTheWindowByWhetherTheTargetIsCurrent() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 1)

        XCTAssertTrue(placement.move(win.snapshot(), to: 2))
        XCTAssertEqual(workspaces.workspace(for: 100), 2)
        XCTAssertTrue(placement.isParked(100))

        XCTAssertTrue(placement.move(win.snapshot(), to: 1))
        XCTAssertFalse(placement.isParked(100))
    }

    func testAParkedWindowIsNotParkedAgain() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 2)
        desktop.clearCalls()

        XCTAssertTrue(placement.move(win.snapshot(), to: 3))

        XCTAssertTrue(placement.isParked(100))
        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testMoveRefusesAWindowItCannotManage() {
        let win = add(StubWindow(id: 200, isFullScreen: true))

        XCTAssertFalse(placement.move(win.snapshot(), to: 2))
        XCTAssertTrue(desktop.reframeCalls.isEmpty)
        XCTAssertEqual(workspaces.allWindowIds, [])
    }

    func testRestoreParkedWindowsActivatesEveryParkedWindowWhereItIs() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))
        placement.assign(win1.snapshot(), to: 2)
        placement.assign(win2.snapshot(), to: 3)

        placement.restoreParkedWindows()

        XCTAssertFalse(placement.isParked(100))
        XCTAssertFalse(placement.isParked(200))
        XCTAssertEqual(workspaces.workspace(for: 100), 2)
    }

    func testDropsAWindowTheScreenNoLongerShowsWhileAParkedWindowIsOnScreen() {
        seedActiveAndParkedWindows()

        offScreenWindowIds = [100]
        placement.dropWindowsThatLeftTheDesktop()

        XCTAssertEqual(workspaces.allWindowIds, [200])
    }

    func testKeepsAParkedWindowTheScreenNoLongerShows() {
        seedActiveAndParkedWindows()
        let alsoParked = add(StubWindow(id: 300))
        placement.assign(alsoParked.snapshot(), to: 2)

        offScreenWindowIds = [300]
        placement.dropWindowsThatLeftTheDesktop()

        XCTAssertEqual(workspaces.allWindowIds, [100, 200, 300])
    }

    func testDropsNothingWhileNoParkedWindowIsOnScreen() {
        seedActiveAndParkedWindows()

        offScreenWindowIds = [100, 200]
        placement.dropWindowsThatLeftTheDesktop()

        XCTAssertEqual(workspaces.allWindowIds, [100, 200])
    }

    func testKeepsATabHiddenByItsSibling() {
        seedActiveAndParkedWindows()
        let tab1 = add(StubWindow(id: 300, appName: "Terminal", frame: tabFrame, tabCount: 2))
        let tab2 = add(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))
        placement.assign(tab1.snapshot(), to: 1)
        placement.assign(tab2.snapshot(), to: 1)

        offScreenWindowIds = [300]
        placement.dropWindowsThatLeftTheDesktop()

        XCTAssertEqual(workspaces.allWindowIds, [100, 200, 300, 301])
    }

    func testKeepsAWindowThatWentFullScreen() {
        let (active, _) = seedActiveAndParkedWindows()

        active.isFullScreen = true
        offScreenWindowIds = [100]
        placement.dropWindowsThatLeftTheDesktop()

        XCTAssertEqual(workspaces.allWindowIds, [100, 200])
    }

    func testReleaseToFullScreenRecordsTheWorkspaceTheWindowLeaves() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 1)

        win.isFullScreen = true
        placement.releaseToFullScreen(100, from: 1)

        XCTAssertNil(workspaces.workspace(for: 100))
        XCTAssertEqual(workspaces.membership(of: win.snapshot(), whenNew: 2), .fullScreen(1))
    }

    func testFollowBackFromFullScreenSwitchesToTheWorkspaceBeforeAssigning() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 1)
        placement.releaseToFullScreen(100, from: 1)
        placement.switchTo(2)

        XCTAssertTrue(placement.followBackFromFullScreen(win.snapshot(), to: 1))
        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(workspaces.workspace(for: 100), 1)
        XCTAssertFalse(placement.isParked(100))
    }

    func testFollowBackFromFullScreenLeavesTheWorkspaceForAWindowItCannotManage() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 1)
        placement.releaseToFullScreen(100, from: 1)
        placement.switchTo(2)

        win.isFullScreen = true

        XCTAssertFalse(placement.followBackFromFullScreen(win.snapshot(), to: 1))
        XCTAssertEqual(workspaces.current, 2)
    }

    @discardableResult
    private func seedActiveAndParkedWindows() -> (active: StubWindow, parked: StubWindow) {
        let active = add(StubWindow(id: 100))
        let parked = add(StubWindow(id: 200))
        placement.assign(active.snapshot(), to: 1)
        placement.assign(parked.snapshot(), to: 2)
        return (active, parked)
    }
}
