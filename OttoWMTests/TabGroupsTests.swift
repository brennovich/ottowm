import CoreGraphics
import XCTest

final class TabGroupsTests: XCTestCase {
    func testGrouping() {
        let cases: [(name: String, windows: [WindowSnapshot], subject: CGWindowID, expected: [CGWindowID])] = [
            (
                "an unknown window moves alone",
                [],
                999,
                [999]
            ),
            (
                "a window without tabs opens its own group",
                [makeSnapshot(100)],
                100,
                [100]
            ),
            (
                "matching tabbed windows share a group",
                [makeSnapshot(100, tabCount: 2), makeSnapshot(200, tabCount: 2)],
                100,
                [100, 200]
            ),
            (
                "a window of another app opens its own group",
                [makeSnapshot(100, appName: "Safari", tabCount: 2), makeSnapshot(200, appName: "Terminal", tabCount: 2)],
                100,
                [100]
            ),
            (
                "a window elsewhere on screen opens its own group",
                [
                    makeSnapshot(100, tabCount: 2),
                    makeSnapshot(200, frame: CGRect(x: 500, y: 0, width: 800, height: 600), tabCount: 2),
                ],
                200,
                [200]
            ),
            (
                "a window without tabs never joins an existing group",
                [makeSnapshot(100, tabCount: 2), makeSnapshot(200, tabCount: 1)],
                200,
                [200]
            ),
            (
                "a representative captured before its tabs existed still matches",
                [makeSnapshot(100, tabCount: 1), makeSnapshot(200, tabCount: 2)],
                100,
                [100, 200]
            ),
            (
                "adding a known window again keeps its group",
                [makeSnapshot(100, tabCount: 2), makeSnapshot(200, tabCount: 2), makeSnapshot(100, tabCount: 2)],
                100,
                [100, 200]
            ),
        ]

        for testCase in cases {
            var tabGroups = TabGroups()
            for window in testCase.windows {
                tabGroups.add(window)
            }

            XCTAssertEqual(tabGroups.members(of: testCase.subject), testCase.expected, testCase.name)
        }
    }

    func testSiblings() {
        let cases: [(name: String, windows: [WindowSnapshot], subject: CGWindowID, expected: [CGWindowID]?)] = [
            ("an unknown window has no siblings", [], 999, nil),
            ("a window alone in its group has no siblings", [makeSnapshot(100)], 100, nil),
            (
                "the other members of the group",
                [makeSnapshot(100, tabCount: 2), makeSnapshot(200, tabCount: 2), makeSnapshot(300, tabCount: 2)],
                200,
                [100, 300]
            ),
        ]

        for testCase in cases {
            var tabGroups = TabGroups()
            for window in testCase.windows {
                tabGroups.add(window)
            }

            XCTAssertEqual(tabGroups.siblings(of: testCase.subject), testCase.expected, testCase.name)
        }
    }

    func testRemoveDetachesTheWindowFromItsGroup() {
        var tabGroups = TabGroups()
        tabGroups.add(makeSnapshot(100, tabCount: 2))
        tabGroups.add(makeSnapshot(200, tabCount: 2))

        tabGroups.remove(100)

        XCTAssertEqual(tabGroups.members(of: 100), [100])
        XCTAssertNil(tabGroups.siblings(of: 100))
        XCTAssertEqual(tabGroups.members(of: 200), [200])
        XCTAssertNil(tabGroups.siblings(of: 200))
    }

    func testRemovingEveryMemberRetiresTheGroup() {
        var tabGroups = TabGroups()
        tabGroups.add(makeSnapshot(100, tabCount: 2))
        tabGroups.add(makeSnapshot(200, tabCount: 2))

        tabGroups.remove(100)
        tabGroups.remove(200)
        tabGroups.add(makeSnapshot(300, tabCount: 2))

        XCTAssertEqual(tabGroups.members(of: 300), [300])
    }

    func testRemoveUnknownWindowIsANoOp() {
        var tabGroups = TabGroups()
        tabGroups.add(makeSnapshot(100, tabCount: 2))
        tabGroups.add(makeSnapshot(200, tabCount: 2))

        tabGroups.remove(999)

        XCTAssertEqual(tabGroups.members(of: 100), [100, 200])
    }
}
