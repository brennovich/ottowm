import CoreGraphics
import XCTest

final class ManagedWindowsTests: EngineTestCase {
    func testOnlyAnAdmissibleWindowOnScreenIsAssigned() {
        offScreenWindowIds = [500]
        let offScreen = add(StubWindow(id: 500))
        let admissible = add(StubWindow(id: 600))

        XCTAssertNil(managed.assign(offScreen.snapshot(), to: 1))
        XCTAssertEqual(managed.assign(admissible.snapshot(), to: 1), 1)
        XCTAssertEqual(workspaces.allWindowIds, [600])
    }

    func testAssignReportsTheWorkspaceOfAKnownWindowAndLeavesItThere() {
        let win = add(StubWindow(id: 100))
        managed.assign(win.snapshot(), to: 2)
        desktop.clearCalls()

        XCTAssertEqual(managed.assign(win.snapshot(), to: 1), 2)
        XCTAssertEqual(workspaces.workspace(for: 100), 2)
        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testNothingIsAssignedWhileAnotherNativeSpaceIsInFront() {
        let win = add(StubWindow(id: 100))
        managed.assign(win.snapshot(), to: 1)
        offScreenWindowIds = [100]
        desktop.clearCalls()

        let other = add(StubWindow(id: 200))

        XCTAssertFalse(managed.isDesktopInFront)
        XCTAssertNil(managed.assign(other.snapshot(), to: 1))
        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testTheDesktopIsInFrontWhenTheFocusedWindowBelongsToAManagedTabGroup() {
        let tab1 = add(StubWindow(id: 300, appName: "Terminal", frame: tabFrame, tabCount: 2))
        managed.assign(tab1.snapshot(), to: 1)
        let tab2 = add(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))
        offScreenWindowIds = [300]

        focused = add(StubWindow(id: 100))

        XCTAssertFalse(managed.isDesktopInFront)

        focused = tab2

        XCTAssertTrue(managed.isDesktopInFront)
    }

    func testAssignPlacesAWindowByTheWorkspaceItsTabGroupHolds() {
        let tab1 = add(StubWindow(id: 300, appName: "Terminal", frame: tabFrame, tabCount: 2))
        managed.assign(tab1.snapshot(), to: 1)
        managed.switchTo(2)
        let tab2 = add(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))

        XCTAssertEqual(managed.assign(tab2.snapshot(), to: 2), 1)
        XCTAssertTrue(managed.isParked(301))
    }

    func testUnmanageHandsAParkedWindowBackToTheDesktop() {
        let parked = add(StubWindow(id: 100))
        let onDesk = add(StubWindow(id: 200))
        managed.assign(parked.snapshot(), to: 2)
        managed.assign(onDesk.snapshot(), to: 1)
        desktop.clearCalls()

        managed.unmanage(100, reason: "test")

        XCTAssertEqual(desktop.reframeCalls.map(\.windowId), [100])
        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.unpark(parked.frame)])
        XCTAssertFalse(managed.isParked(100))

        desktop.clearCalls()
        managed.unmanage(200, reason: "test")

        XCTAssertTrue(desktop.reframeCalls.isEmpty)
        XCTAssertEqual(workspaces.allWindowIds, [])
    }

    func testUnmanageForgetsTheParkedFrameOfAWindowTheDesktopReportsGone() {
        let win = add(StubWindow(id: 200))
        managed.assign(win.snapshot(), to: 2)

        windows[200] = nil
        managed.unmanage(200, reason: "test")

        XCTAssertFalse(managed.isParked(200))
    }

    func testUnmanageReportsTheFocusSettledForAWindowItNeverManaged() {
        let win = add(StubWindow(id: 100))
        managed.assign(win.snapshot(), to: 1)

        XCTAssertTrue(managed.unmanage(900, reason: "test"))
        XCTAssertFalse(managed.unmanage(100, reason: "test"))
    }

    func testSwitchToParksTheWindowsLeftAndActivatesTheTargetsInOneBatch() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))
        managed.assign(win1.snapshot(), to: 1)
        managed.assign(win2.snapshot(), to: 2)
        desktop.clearCalls()

        managed.switchTo(2)

        XCTAssertEqual(workspaces.current, 2)
        XCTAssertTrue(managed.isParked(100))
        XCTAssertFalse(managed.isParked(200))
        XCTAssertEqual(desktop.reframeBatches.map(Set.init), [[100, 200]])
    }

    func testSwitchToUnmanagesTheWindowsTheDesktopReportsGone() {
        let win1 = add(StubWindow(id: 100))
        let doomed = add(StubWindow(id: 300))
        managed.assign(win1.snapshot(), to: 1)
        managed.assign(doomed.snapshot(), to: 2)

        windows[300] = nil
        managed.switchTo(2)

        XCTAssertNil(workspaces.workspace(for: 300))
        XCTAssertFalse(managed.isParked(300))
    }

    func testSwitchToRecordsTheFocusOnTheManageableWindowFocusedWhenLeaving() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))
        managed.assign(win1.snapshot(), to: 1)
        managed.assign(win2.snapshot(), to: 1)

        focused = win1
        managed.switchTo(2)
        managed.switchTo(1)

        XCTAssertEqual(workspaces.nextWindowToFocus, 100)

        offScreenWindowIds = [200]
        focused = win2
        managed.switchTo(2)
        managed.switchTo(1)

        XCTAssertEqual(workspaces.nextWindowToFocus, 100)
    }

    func testMovePlacesTheWindowByWhetherTheTargetIsCurrent() {
        let win = add(StubWindow(id: 100))
        managed.assign(win.snapshot(), to: 1)

        XCTAssertTrue(managed.move(win.snapshot(), to: 2))
        XCTAssertEqual(workspaces.workspace(for: 100), 2)
        XCTAssertTrue(managed.isParked(100))

        XCTAssertTrue(managed.move(win.snapshot(), to: 1))
        XCTAssertFalse(managed.isParked(100))
    }

    func testAParkedWindowIsNotParkedAgain() {
        let win = add(StubWindow(id: 100))
        managed.assign(win.snapshot(), to: 2)
        desktop.clearCalls()

        XCTAssertTrue(managed.move(win.snapshot(), to: 3))

        XCTAssertTrue(managed.isParked(100))
        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testMoveRefusesAWindowItCannotManage() {
        let win = add(StubWindow(id: 200, isFullScreen: true))

        XCTAssertFalse(managed.move(win.snapshot(), to: 2))
        XCTAssertTrue(desktop.reframeCalls.isEmpty)
        XCTAssertEqual(workspaces.allWindowIds, [])
    }

    func testRestoreParkedWindowsActivatesEveryParkedWindowWhereItIs() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))
        managed.assign(win1.snapshot(), to: 2)
        managed.assign(win2.snapshot(), to: 3)

        managed.restoreParkedWindows()

        XCTAssertFalse(managed.isParked(100))
        XCTAssertFalse(managed.isParked(200))
        XCTAssertEqual(workspaces.workspace(for: 100), 2)
    }

    func testDropsAWindowTheScreenNoLongerShowsWhileAParkedWindowIsOnScreen() {
        seedActiveAndParkedWindows()

        offScreenWindowIds = [100]
        managed.dropWindowsThatLeftTheDesktop()

        XCTAssertEqual(workspaces.allWindowIds, [200])
    }

    func testKeepsAParkedWindowTheScreenNoLongerShows() {
        seedActiveAndParkedWindows()
        let alsoParked = add(StubWindow(id: 300))
        managed.assign(alsoParked.snapshot(), to: 2)

        offScreenWindowIds = [300]
        managed.dropWindowsThatLeftTheDesktop()

        XCTAssertEqual(workspaces.allWindowIds, [100, 200, 300])
    }

    func testDropsNothingWhileNoParkedWindowIsOnScreen() {
        seedActiveAndParkedWindows()

        offScreenWindowIds = [100, 200]
        managed.dropWindowsThatLeftTheDesktop()

        XCTAssertEqual(workspaces.allWindowIds, [100, 200])
    }

    func testKeepsATabHiddenByItsSibling() {
        seedActiveAndParkedWindows()
        let tab1 = add(StubWindow(id: 300, appName: "Terminal", frame: tabFrame, tabCount: 2))
        let tab2 = add(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))
        managed.assign(tab1.snapshot(), to: 1)
        managed.assign(tab2.snapshot(), to: 1)

        offScreenWindowIds = [300]
        managed.dropWindowsThatLeftTheDesktop()

        XCTAssertEqual(workspaces.allWindowIds, [100, 200, 300, 301])
    }

    func testKeepsAWindowThatWentFullScreen() {
        let (active, _) = seedActiveAndParkedWindows()

        active.isFullScreen = true
        offScreenWindowIds = [100]
        managed.dropWindowsThatLeftTheDesktop()

        XCTAssertEqual(workspaces.allWindowIds, [100, 200])
    }

    func testReleaseToFullScreenRecordsTheWorkspaceTheWindowLeaves() {
        let win = add(StubWindow(id: 100))
        managed.assign(win.snapshot(), to: 1)

        win.isFullScreen = true
        managed.releaseToFullScreen(100, from: 1)

        XCTAssertNil(workspaces.workspace(for: 100))
        XCTAssertEqual(workspaces.membership(of: win.snapshot(), whenNew: 2), .fullScreen(1))
    }

    func testFollowBackFromFullScreenSwitchesToTheWorkspaceBeforeAssigning() {
        let win = add(StubWindow(id: 100))
        managed.assign(win.snapshot(), to: 1)
        managed.releaseToFullScreen(100, from: 1)
        managed.switchTo(2)

        XCTAssertTrue(managed.followBackFromFullScreen(win.snapshot(), to: 1))
        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(workspaces.workspace(for: 100), 1)
        XCTAssertFalse(managed.isParked(100))
    }

    func testFollowBackFromFullScreenLeavesTheWorkspaceForAWindowItCannotManage() {
        let win = add(StubWindow(id: 100))
        managed.assign(win.snapshot(), to: 1)
        managed.releaseToFullScreen(100, from: 1)
        managed.switchTo(2)

        win.isFullScreen = true

        XCTAssertFalse(managed.followBackFromFullScreen(win.snapshot(), to: 1))
        XCTAssertEqual(workspaces.current, 2)
    }

    @discardableResult
    private func seedActiveAndParkedWindows() -> (active: StubWindow, parked: StubWindow) {
        let active = add(StubWindow(id: 100))
        let parked = add(StubWindow(id: 200))
        managed.assign(active.snapshot(), to: 1)
        managed.assign(parked.snapshot(), to: 2)
        return (active, parked)
    }
}
