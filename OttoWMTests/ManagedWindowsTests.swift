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

    func testNothingIsAssignedWhileAnotherNativeSpaceIsInFront() {
        let win = add(StubWindow(id: 100))
        managed.assign(win.snapshot(), to: 1)
        offScreenWindowIds = [100]
        desktop.clearPlaceCalls()

        let other = add(StubWindow(id: 200))

        XCTAssertFalse(managed.isDesktopInFront)
        XCTAssertNil(managed.assign(other.snapshot(), to: 1))
        XCTAssertTrue(desktop.placeCalls.isEmpty)
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
        XCTAssertEqual(managed.placement(of: 301), .parked)
    }

    func testUnmanageHandsAParkedWindowBackToTheDesktop() {
        let parked = add(StubWindow(id: 100))
        let onDesk = add(StubWindow(id: 200))
        managed.assign(parked.snapshot(), to: 2)
        managed.assign(onDesk.snapshot(), to: 1)
        desktop.clearPlaceCalls()

        managed.unmanage(100, reason: "test")

        XCTAssertEqual(desktop.placeCalls.map(\.windowId), [100])
        XCTAssertEqual(desktop.placeCalls.map(\.placement), [.active])
        XCTAssertEqual(managed.placement(of: 100), .active)

        desktop.clearPlaceCalls()
        managed.unmanage(200, reason: "test")

        XCTAssertTrue(desktop.placeCalls.isEmpty)
        XCTAssertEqual(workspaces.allWindowIds, [])
    }

    func testUnmanageForgetsTheParkedFrameOfAWindowTheDesktopReportsGone() {
        let win = add(StubWindow(id: 200))
        managed.assign(win.snapshot(), to: 2)

        windows[200] = nil
        managed.unmanage(200, reason: "test")

        XCTAssertEqual(managed.placement(of: 200), .active)
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
        desktop.clearPlaceCalls()

        managed.switchTo(2)

        XCTAssertEqual(workspaces.current, 2)
        XCTAssertEqual(managed.placement(of: 100), .parked)
        XCTAssertEqual(managed.placement(of: 200), .active)
        XCTAssertEqual(desktop.placeBatches.map(Set.init), [[100, 200]])
    }

    func testSwitchToUnmanagesTheWindowsTheDesktopReportsGone() {
        let win1 = add(StubWindow(id: 100))
        let doomed = add(StubWindow(id: 300))
        managed.assign(win1.snapshot(), to: 1)
        managed.assign(doomed.snapshot(), to: 2)

        windows[300] = nil
        managed.switchTo(2)

        XCTAssertNil(workspaces.workspace(for: 300))
        XCTAssertEqual(managed.placement(of: 300), .active)
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
        XCTAssertEqual(managed.placement(of: 100), .parked)

        XCTAssertTrue(managed.move(win.snapshot(), to: 1))
        XCTAssertEqual(managed.placement(of: 100), .active)
    }

    func testMoveRefusesAWindowItCannotManage() {
        let win = add(StubWindow(id: 200, isFullScreen: true))

        XCTAssertFalse(managed.move(win.snapshot(), to: 2))
        XCTAssertTrue(desktop.placeCalls.isEmpty)
        XCTAssertEqual(workspaces.allWindowIds, [])
    }

    func testRestoreParkedWindowsActivatesEveryParkedWindowWhereItIs() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))
        managed.assign(win1.snapshot(), to: 2)
        managed.assign(win2.snapshot(), to: 3)

        managed.restoreParkedWindows()

        XCTAssertEqual(managed.placement(of: 100), .active)
        XCTAssertEqual(managed.placement(of: 200), .active)
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
        XCTAssertEqual(managed.placement(of: 100), .active)
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
