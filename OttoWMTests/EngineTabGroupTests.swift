import CoreGraphics
import XCTest

final class EngineTabGroupTests: EngineTestCase {
    func testStartGroupsTabsAgainstTheFrameTheyWereRecoveredTo() {
        let hiddenEdge = CGRect(x: 1791, y: 1082, width: 908, height: 798)
        let recovered = CGRect(x: 442, y: 161, width: 908, height: 798)
        let parkedTab = add(StubWindow(id: 300, appName: "Terminal", frame: hiddenEdge, tabCount: 2))
        desktop.recoveredFrames = [300: recovered]

        engine.start(windows: [parkedTab.snapshot()])
        let lateTab = add(StubWindow(id: 301, appName: "Terminal", frame: recovered, tabCount: 2))
        engine.handle(.focused(lateTab.snapshot()))

        workspaces.move(300, to: 2)
        XCTAssertEqual(workspaces.workspace(for: 301), 2)
    }

    func testSelectingAnotherTabKeepsTheDesktopInFront() {
        let tab1 = create(StubWindow(id: 300, appName: "Terminal", frame: tabFrame, tabCount: 2))
        let tab2 = add(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))
        offScreenWindowIds = [300]
        focused = tab2

        engine.switchToWorkspace(2)

        XCTAssertEqual(workspaces.workspace(for: 301), 1)
        XCTAssertEqual(parkedWindows.placement(of: 301), .parked)
        XCTAssertEqual(tab1.focusCount, 0)
    }

    func testTabHiddenBySiblingIsNotDroppedAsHavingLeftTheDesktop() {
        create(StubWindow(id: 300, appName: "Terminal", frame: tabFrame, tabCount: 2))
        let tab2 = create(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))
        let other = create(StubWindow(id: 100))
        moveFocusedWindow(other, to: 2)

        focused = tab2
        offScreenWindowIds = [300]
        engine.switchToWorkspace(2)

        XCTAssertEqual(workspaces.workspace(for: 300), 1)
        XCTAssertEqual(parkedWindows.placement(of: 300), .parked)
    }

    func testFocusingATabOfAGroupParkedElsewhereFollowsTheUserToIt() {
        create(StubWindow(id: 300, appName: "Terminal", frame: tabFrame, tabCount: 2))
        engine.switchToWorkspace(2)

        let lateTab = add(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))
        focused = lateTab
        engine.handle(.focused(lateTab.snapshot()))

        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(parkedWindows.placement(of: 301), .active)
    }

    func testDestroyedTabbedWindowDoesNotStealFocus() {
        let (tab1, _, other) = createFocusedTabPair()

        windows[301] = nil
        engine.handle(.destroyed(301))

        XCTAssertEqual(tab1.focusCount, 0)
        XCTAssertEqual(other.focusCount, 0)
    }

    func testTabSiblingKeepsFocusWhenSeparateWindowCloses() {
        let tab1 = create(StubWindow(id: 300, appName: "Terminal", frame: tabFrame))
        let tab2 = create(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))
        engine.handle(.focused(tab1.snapshot()))
        let other = create(StubWindow(id: 100))
        engine.handle(.focused(other.snapshot()))

        focused = tab2
        windows[100] = nil
        engine.handle(.destroyed(100))

        XCTAssertEqual(tab1.focusCount, 0)
        XCTAssertEqual(tab2.focusCount, 0)

        focused = nil
        engine.switchToWorkspace(2)
        engine.switchToWorkspace(1)

        XCTAssertEqual(tab2.focusCount, 1)
        XCTAssertEqual(tab1.focusCount, 0)
    }
}
