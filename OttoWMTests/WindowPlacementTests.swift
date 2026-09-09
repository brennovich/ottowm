import CoreGraphics
import XCTest

final class WindowPlacementTests: EngineTestCase {
    func testAssignTakesOnlyAWindowAdmissionAdmits() {
        offScreenWindowIds = [500]
        let offScreen = add(StubWindow(id: 500))
        let admitted = add(StubWindow(id: 600))

        XCTAssertEqual(placement.assign(offScreen.snapshot(), to: 1), .refused(.retry))
        XCTAssertTrue(desktop.reframeCalls.isEmpty)

        XCTAssertEqual(placement.assign(admitted.snapshot(), to: 1), .assigned(1))
        XCTAssertEqual(workspaces.allWindowIds, [600])
    }

    func testAssignReportsAWindowItsShapeRulesOutAsRefusedForGood() {
        let fullScreen = add(StubWindow(id: 500, isFullScreen: true))

        XCTAssertEqual(placement.assign(fullScreen.snapshot(), to: 1), .refused(.refuse))
    }

    func testAssignReportsTheWorkspaceOfAKnownWindowAndLeavesItThere() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 2)
        desktop.clearCalls()

        XCTAssertEqual(placement.assign(win.snapshot(), to: 1), .assigned(2))
        XCTAssertEqual(workspaces.workspace(for: 100), 2)
        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testAssignPlacesAWindowByTheWorkspaceItsTabGroupHolds() {
        let tab1 = add(StubWindow(id: 300, appName: "Terminal", frame: tabFrame, tabCount: 2))
        placement.assign(tab1.snapshot(), to: 1)
        placement.switchTo(2)
        let tab2 = add(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))

        XCTAssertEqual(placement.assign(tab2.snapshot(), to: 2), .assigned(1))
        XCTAssertTrue(placement.isParked(301))
    }

    /// macOS reports no merge, so the group of a window merged into another window's tabs
    /// since it was assigned is matched before it moves, and every tab of that window moves
    /// with it.
    func testMoveTakesTheTabsAWindowWasMergedIntoSinceItWasAssigned() {
        let host = add(StubWindow(id: 300, appName: "Terminal", frame: tabFrame))
        let apart = add(StubWindow(id: 301, appName: "Terminal", frame: CGRect(x: 1200, y: 0, width: 800, height: 600)))
        placement.assign(host.snapshot(), to: 1)
        placement.assign(apart.snapshot(), to: 1)

        apart.tabs = 2
        apart.moveTo(tabFrame)
        placement.move(apart.snapshot(), to: 2)

        XCTAssertEqual(workspaces.workspace(for: 300), 2)
    }

    func testDropHandsAParkedWindowBackToTheDesktop() {
        let parked = add(StubWindow(id: 100))
        let onDesk = add(StubWindow(id: 200))
        placement.assign(parked.snapshot(), to: 2)
        placement.assign(onDesk.snapshot(), to: 1)
        desktop.clearCalls()

        placement.drop(100, reason: "test")

        XCTAssertEqual(desktop.reframeCalls.map(\.windowId), [100])
        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.unpark(parked.frame)])
        XCTAssertFalse(placement.isParked(100))

        desktop.clearCalls()
        placement.drop(200, reason: "test")

        XCTAssertTrue(desktop.reframeCalls.isEmpty)
        XCTAssertEqual(workspaces.allWindowIds, [])
    }

    func testDropForgetsTheParkedFrameOfAWindowTheDesktopReportsGone() {
        let win = add(StubWindow(id: 200))
        placement.assign(win.snapshot(), to: 2)

        windows[200] = nil
        placement.drop(200, reason: "test")

        XCTAssertFalse(placement.isParked(200))
    }

    func testDropReportsTheFocusSettledForAWindowItNeverManaged() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 1)

        XCTAssertTrue(placement.drop(900, reason: "test"))
        XCTAssertFalse(placement.drop(100, reason: "test"))
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

    func testSwitchToDropsTheWindowsTheDesktopReportsGone() {
        let win1 = add(StubWindow(id: 100))
        let doomed = add(StubWindow(id: 300))
        placement.assign(win1.snapshot(), to: 1)
        placement.assign(doomed.snapshot(), to: 2)

        windows[300] = nil
        placement.switchTo(2)

        XCTAssertNil(workspaces.workspace(for: 300))
        XCTAssertFalse(placement.isParked(300))
    }

    func testSwitchToRecordsTheFocusOnTheAdmissibleWindowFocusedWhenLeaving() {
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

    func testMoveRefusesAWindowItCannotAdmit() {
        let win = add(StubWindow(id: 200, isFullScreen: true))

        XCTAssertFalse(placement.move(win.snapshot(), to: 2))
        XCTAssertTrue(desktop.reframeCalls.isEmpty)
        XCTAssertEqual(workspaces.allWindowIds, [])
    }

    func testReframeHandsTheChangeTheFrameARestoreGoesBackTo() {
        let frame = CGRect(x: 400, y: 300, width: 200, height: 200)
        let win = add(StubWindow(id: 100, frame: frame))
        placement.assign(win.snapshot(), to: 1)
        desktop.clearCalls()

        placement.reframe(win.snapshot()) { .maximize(restoring: $0) }
        placement.reframe(win.snapshot()) { .maximize(restoring: $0) }

        XCTAssertEqual(desktop.reframeCalls.map(\.windowId), [100, 100])
        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.maximize(restoring: nil), .maximize(restoring: frame)])
    }

    func testReframeWithAnyOtherChangeLeavesNothingToRestore() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 1)
        placement.reframe(win.snapshot()) { .maximize(restoring: $0) }
        placement.reframe(win.snapshot()) { _ in .step(Step(direction: .east, points: 15)) }
        desktop.clearCalls()

        placement.reframe(win.snapshot()) { .maximize(restoring: $0) }

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.maximize(restoring: nil)])
    }

    func testReframeDropsAWindowTheDesktopReportsGone() {
        let win = add(StubWindow(id: 100))
        placement.assign(win.snapshot(), to: 1)

        windows[100] = nil
        placement.reframe(win.snapshot()) { _ in .center }

        XCTAssertNil(workspaces.workspace(for: 100))
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

    func testClosedWindowsAreTheCurrentWorkspaceWindowsTheScreenNoLongerShows() {
        let cases: [(name: String, workspace: Int, prepare: (StubWindow) -> Void, closed: [CGWindowID])] = [
            ("off screen", 1, { _ in }, [100]),
            ("minimized", 1, { $0.isMinimized = true }, []),
            ("full screen", 1, { $0.isFullScreen = true }, []),
            ("parked in another workspace", 2, { _ in }, []),
            ("no snapshot", 1, { _ in self.windows[100] = nil }, []),
        ]

        for testCase in cases {
            let win = add(StubWindow(id: 100))
            placement.assign(win.snapshot(), to: testCase.workspace)
            testCase.prepare(win)
            offScreenWindowIds = [100]

            XCTAssertEqual(placement.closedWindows(), testCase.closed, testCase.name)

            placement.drop(100, reason: "test")
        }
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

    func testFollowBackFromFullScreenLeavesTheWorkspaceForAWindowItCannotAdmit() {
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
