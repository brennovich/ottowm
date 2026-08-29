import CoreGraphics
import XCTest

final class TabGroupsTests: XCTestCase {
    private struct TabbedWindow {
        let snapshot: WindowSnapshot
        let tabCount: Int
    }

    private func tabbed(
        _ id: CGWindowID,
        appName: String = "App",
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
        tabCount: Int = 1
    ) -> TabbedWindow {
        TabbedWindow(snapshot: makeSnapshot(id, appName: appName, frame: frame), tabCount: tabCount)
    }

    private var tabCounts: [CGWindowID: Int] = [:]

    private func makeTabGroups(_ windows: [TabbedWindow]) -> TabGroups {
        tabCounts = [:]
        var tabGroups = TabGroups(tabCount: { [weak self] in self?.tabCounts[$0] ?? 1 })
        for window in windows {
            add(window, to: &tabGroups)
        }
        return tabGroups
    }

    private func add(_ window: TabbedWindow, to tabGroups: inout TabGroups) {
        tabCounts[window.snapshot.id] = window.tabCount
        tabGroups.add(window.snapshot)
    }

    func testGrouping() {
        let cases: [(name: String, windows: [TabbedWindow], subject: CGWindowID, expected: [CGWindowID])] = [
            ("an unknown window moves alone", [], 999, [999]),
            ("a window without tabs opens its own group", [tabbed(100)], 100, [100]),
            ("matching tabbed windows share a group", [tabbed(100, tabCount: 2), tabbed(200, tabCount: 2)], 100, [100, 200]),
            (
                "a window of another app opens its own group",
                [tabbed(100, appName: "Safari", tabCount: 2), tabbed(200, appName: "Terminal", tabCount: 2)],
                100,
                [100]
            ),
            (
                "a window elsewhere on screen opens its own group",
                [tabbed(100, tabCount: 2), tabbed(200, frame: CGRect(x: 500, y: 0, width: 800, height: 600), tabCount: 2)],
                200,
                [200]
            ),
            (
                "a window nudged within the y tolerance joins the group",
                [tabbed(100, tabCount: 2), tabbed(200, frame: CGRect(x: 0, y: 10, width: 800, height: 600), tabCount: 2)],
                100,
                [100, 200]
            ),
            (
                "a window past the y tolerance opens its own group",
                [tabbed(100, tabCount: 2), tabbed(200, frame: CGRect(x: 0, y: 11, width: 800, height: 600), tabCount: 2)],
                200,
                [200]
            ),
            (
                "a window of another size opens its own group",
                [tabbed(100, tabCount: 2), tabbed(200, frame: CGRect(x: 0, y: 0, width: 801, height: 600), tabCount: 2)],
                200,
                [200]
            ),
            ("a window without tabs never joins an existing group", [tabbed(100, tabCount: 2), tabbed(200, tabCount: 1)], 200, [200]),
            (
                "a representative captured before its tabs existed still matches",
                [tabbed(100, tabCount: 1), tabbed(200, tabCount: 2)],
                100,
                [100, 200]
            ),
            (
                "adding a known window again keeps its group",
                [tabbed(100, tabCount: 2), tabbed(200, tabCount: 2), tabbed(100, tabCount: 2)],
                100,
                [100, 200]
            ),
        ]

        for testCase in cases {
            XCTAssertEqual(makeTabGroups(testCase.windows).members(of: testCase.subject), testCase.expected, testCase.name)
        }
    }

    func testSiblings() {
        let cases: [(name: String, windows: [TabbedWindow], subject: CGWindowID, expected: [CGWindowID])] = [
            ("an unknown window has no siblings", [], 999, []),
            ("a window alone in its group has no siblings", [tabbed(100)], 100, []),
            (
                "the other members of the group",
                [tabbed(100, tabCount: 2), tabbed(200, tabCount: 2), tabbed(300, tabCount: 2)],
                200,
                [100, 300]
            ),
        ]

        for testCase in cases {
            XCTAssertEqual(makeTabGroups(testCase.windows).siblings(of: testCase.subject), testCase.expected, testCase.name)
        }
    }

    func testRemoveDetachesTheWindowFromItsGroup() {
        var tabGroups = makeTabGroups([tabbed(100, tabCount: 2), tabbed(200, tabCount: 2)])

        tabGroups.remove(100)

        XCTAssertEqual(tabGroups.members(of: 100), [100])
        XCTAssertEqual(tabGroups.siblings(of: 100), [])
        XCTAssertEqual(tabGroups.members(of: 200), [200])
        XCTAssertEqual(tabGroups.siblings(of: 200), [])
    }

    func testRemovingEveryMemberRetiresTheGroup() {
        var tabGroups = makeTabGroups([tabbed(100, tabCount: 2), tabbed(200, tabCount: 2)])

        tabGroups.remove(100)
        tabGroups.remove(200)
        add(tabbed(300, tabCount: 2), to: &tabGroups)

        XCTAssertEqual(tabGroups.members(of: 300), [300])
    }

    func testRemoveUnknownWindowIsANoOp() {
        var tabGroups = makeTabGroups([tabbed(100, tabCount: 2), tabbed(200, tabCount: 2)])

        tabGroups.remove(999)

        XCTAssertEqual(tabGroups.members(of: 100), [100, 200])
    }
}
