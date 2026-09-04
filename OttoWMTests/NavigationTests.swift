import CoreGraphics
import XCTest

final class NavigationTests: EngineTestCase {
    func testFollowingAParkedWindowSwitchesToItsWorkspace() {
        let win = add(StubWindow(id: 700))
        managed.assign(win.snapshot(), to: 1)
        managed.switchTo(2)

        focused = win
        navigation.follow(win.snapshot())

        XCTAssertEqual(workspaces.current, 1)
    }

    func testAStaleFocusEventForAParkedWindowIsIgnored() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))
        managed.assign(win1.snapshot(), to: 1)
        managed.assign(win2.snapshot(), to: 2)

        focused = win1
        navigation.follow(win2.snapshot())

        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(managed.placement(of: 200), .parked)
    }

    func testFollowingAParkedWindowDoesNotSwitchWhenACurrentWorkspaceWindowLeftTheScreen() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))
        managed.assign(win1.snapshot(), to: 1)
        managed.assign(win2.snapshot(), to: 2)

        offScreenWindowIds = [100]
        focused = win2
        navigation.follow(win2.snapshot())

        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(managed.placement(of: 200), .parked)
        XCTAssertEqual(workspaces.allWindowIds, [200])
    }

    func testFollowingAParkedWindowDropsTheClosedWindowAndFocusesASurvivor() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))
        let survivor = add(StubWindow(id: 101))
        managed.assign(win1.snapshot(), to: 1)
        managed.assign(win2.snapshot(), to: 2)
        managed.assign(survivor.snapshot(), to: 1)

        windows[100] = nil
        focused = win2
        navigation.follow(win2.snapshot())

        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(workspaces.allWindowIds, [101, 200])
        XCTAssertEqual(survivor.focusCount, 1)
    }

    func testFollowingAParkedWindowSwitchesWhenTheCurrentWorkspaceWindowIsOnlyMinimized() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))
        managed.assign(win1.snapshot(), to: 1)
        managed.assign(win2.snapshot(), to: 2)

        win1.isMinimized = true
        offScreenWindowIds = [100]
        focused = win2
        navigation.follow(win2.snapshot())

        XCTAssertEqual(workspaces.current, 2)
        XCTAssertEqual(managed.placement(of: 200), .active)
    }

    func testFollowingAnUnknownWindowAssignsItToTheCurrentWorkspace() {
        managed.switchTo(2)
        let win = add(StubWindow(id: 100))

        navigation.follow(win.snapshot())

        XCTAssertEqual(workspaces.workspace(for: 100), 2)
        XCTAssertEqual(workspaces.current, 2)
    }

    func testFollowingAWindowNotYetOnScreenLeavesItToTheEnrollmentRetry() {
        offScreenWindowIds = [100]
        let win = add(StubWindow(id: 100))

        navigation.follow(win.snapshot())

        XCTAssertEqual(workspaces.allWindowIds, [])
        XCTAssertFalse(scheduledRetries.isEmpty)
    }

    func testFollowingAWindowBackFromFullScreenTakesTheDesktopToTheWorkspaceItLeft() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))
        managed.assign(win1.snapshot(), to: 1)
        managed.assign(win2.snapshot(), to: 1)
        managed.releaseToFullScreen(200, from: 1)
        managed.switchTo(2)

        navigation.follow(win2.snapshot())

        XCTAssertEqual(workspaces.current, 1)
    }

    func testFollowingATabOfAGroupParkedElsewhereSwitchesToItsWorkspace() {
        let tab1 = add(StubWindow(id: 300, appName: "Terminal", frame: tabFrame, tabCount: 2))
        managed.assign(tab1.snapshot(), to: 1)
        managed.switchTo(2)

        let lateTab = add(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))
        focused = lateTab
        navigation.follow(lateTab.snapshot())

        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(managed.placement(of: 301), .active)
    }

    func testRestoreFocusesTheWindowFocusedLastInTheCurrentWorkspace() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))
        managed.assign(win1.snapshot(), to: 1)
        navigation.follow(win1.snapshot())
        managed.assign(win2.snapshot(), to: 1)
        managed.unmanage(200, reason: "test")

        XCTAssertTrue(navigation.restore())
        XCTAssertEqual(win1.focusCount, 1)
    }

    func testRestoreReportsNothingToFocusInAnEmptyWorkspace() {
        managed.switchTo(2)

        XCTAssertFalse(navigation.restore())
    }

    func testRestoreKeepsTheFocusOnAWindowOfTheCurrentWorkspaceAndEnrollsAnUnknownOne() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))
        managed.assign(win1.snapshot(), to: 1)
        managed.assign(win2.snapshot(), to: 1)

        focused = win1
        XCTAssertTrue(navigation.restore())
        XCTAssertEqual(workspaces.nextWindowToFocus, 100)
        XCTAssertEqual(win1.focusCount, 0)

        focused = add(StubWindow(id: 300))
        XCTAssertTrue(navigation.restore())
        XCTAssertEqual(workspaces.workspace(for: 300), 1)
    }

    func testRestoreLeavesTheFocusOnAFullScreenWindowOfTheCurrentWorkspace() {
        let win1 = add(StubWindow(id: 100))
        let win2 = add(StubWindow(id: 200))
        managed.assign(win1.snapshot(), to: 1)
        managed.assign(win2.snapshot(), to: 1)
        win1.isFullScreen = true
        focused = win1

        XCTAssertTrue(navigation.restore())
        XCTAssertEqual(win1.focusCount, 0)
        XCTAssertEqual(win2.focusCount, 0)
    }

    func testReturnToDesktopBringsAManagedWindowFrontAndIgnoresTheNavigationItCauses() {
        let parked = [72, 88, 187].map { add(StubWindow(id: $0)) }
        parked.forEach { managed.assign($0.snapshot(), to: 1) }
        managed.switchTo(3)
        offScreenWindowIds = [72, 88, 187]

        navigation.returnToDesktop()

        XCTAssertEqual(parked.reduce(0) { $0 + $1.focusCount }, 1)

        focused = windows[187]
        navigation.follow(windows[187]!.snapshot())

        XCTAssertEqual(workspaces.current, 3)

        navigation.follow(windows[187]!.snapshot())

        XCTAssertEqual(workspaces.current, 1)
    }

    func testFocusedWindowOfCurrentWorkspaceIsNilForNoWindowOrOneOfAnotherWorkspace() {
        let elsewhere = add(StubWindow(id: 900))
        managed.assign(elsewhere.snapshot(), to: 2)

        for reference in [nil, elsewhere] {
            focused = reference

            XCTAssertNil(navigation.focusedWindowOfCurrentWorkspace())
        }
    }

    func testFocusedWindowOfCurrentWorkspaceEnrollsAnUnknownWindowItCanManage() {
        let win = add(StubWindow(id: 900))
        focused = win

        XCTAssertEqual(navigation.focusedWindowOfCurrentWorkspace()?.id, 900)
        XCTAssertEqual(workspaces.workspace(for: 900), 1)

        let unmanageable = add(StubWindow(id: 901))
        offScreenWindowIds = [901]
        focused = unmanageable

        XCTAssertNil(navigation.focusedWindowOfCurrentWorkspace())
        XCTAssertNil(workspaces.workspace(for: 901))
    }
}
