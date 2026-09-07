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

    /// Merging opens no window and posts no notification, so the group of the tab acted on
    /// is matched first: the maximize applies to the window, and the tab brought to the
    /// front restores to the frame the tab it was merged with maximized from.
    func testAMaximizeIsUndoneThroughTheTabItsWindowWasMergedWith() {
        let stood = CGRect(x: 400, y: 300, width: 200, height: 200)
        let host = create(StubWindow(id: 300, appName: "Terminal", frame: stood))
        let merged = create(StubWindow(id: 301, appName: "Terminal", frame: CGRect(x: 1200, y: 0, width: 800, height: 600)))
        focused = host
        engine.handle(.toggleMaximize)

        merged.tabs = 2
        merged.moveTo(host.frame)
        focused = merged
        desktop.clearCalls()
        engine.handle(.toggleMaximize)

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.maximize(restoring: stood)])
    }

    func testSelectingAnotherTabKeepsTheDesktopInFront() {
        let tab1 = create(StubWindow(id: 300, appName: "Terminal", frame: tabFrame, tabCount: 2))
        let tab2 = add(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))
        offScreenWindowIds = [300]
        focused = tab2

        engine.switchToWorkspace(2)

        XCTAssertEqual(tab1.focusCount, 0)
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
