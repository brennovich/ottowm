import CoreGraphics
import XCTest

final class WorkspacesTests: XCTestCase {
    private func makeWindow(
        _ id: CGWindowID,
        tabCount: Int = 1,
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
        appName: String = "TestApp"
    ) -> StubWindow {
        StubWindow(id: id, tabCount: tabCount, frame: frame, appName: appName)
    }

    func testCurrentVirtualSpace() {
        let cases: [(name: String, setValues: [Int], expected: Int)] = [
            ("initial value is 1", [], 1),
            ("set to 2", [2], 2),
            ("set to 3", [3], 3),
            ("multiple sets uses last", [2, 5, 3], 3),
        ]

        for testCase in cases {
            let model = Workspaces()
            for value in testCase.setValues {
                model.setCurrentVirtualSpace(value)
            }

            XCTAssertEqual(model.getCurrentVirtualSpace(), testCase.expected, testCase.name)
        }
    }

    func testFocusedWindowManagement() {
        let cases: [(name: String, saves: [(space: Int, window: CGWindowID?)], expected: [(space: Int, window: CGWindowID?)])] = [
            ("save and get single window", [(1, 100)], [(1, 100)]),
            ("get from non-existent space returns nil", [], [(999, nil)]),
            ("overwrite window in same space", [(1, 100), (1, 200)], [(1, 200)]),
            (
                "multiple virtual spaces",
                [(1, 100), (2, 200), (3, 300)],
                [(1, 100), (2, 200), (3, 300)]
            ),
            ("save nil window", [(1, nil)], [(1, nil)]),
        ]

        for testCase in cases {
            let model = Workspaces()
            for save in testCase.saves {
                model.saveFocusedWindowInVirtualSpace(save.space, save.window)
            }

            for assertion in testCase.expected {
                XCTAssertEqual(
                    model.getFocusedWindowForVirtualSpace(assertion.space),
                    assertion.window,
                    testCase.name
                )
            }
        }
    }

    func testWindowAssignment() {
        let cases: [(name: String, assignments: [(window: CGWindowID, space: Int)], expected: [(window: CGWindowID, space: Int)])] = [
            ("assign single window", [(100, 1)], [(100, 1)]),
            (
                "multiple windows to same space",
                [(100, 1), (200, 1), (300, 2)],
                [(100, 1), (200, 1), (300, 2)]
            ),
            ("reassign window to different space", [(100, 1), (100, 2)], [(100, 2)]),
        ]

        for testCase in cases {
            let model = Workspaces()
            for assignment in testCase.assignments {
                model.assignWindowToVirtualSpace(assignment.window, assignment.space)
            }

            for assertion in testCase.expected {
                XCTAssertEqual(
                    model.getVirtualSpaceForWindow(assertion.window),
                    assertion.space,
                    testCase.name
                )
            }
        }
    }

    func testUnregisterWindowsById() {
        let cases: [(name: String, assigned: Bool, windowId: CGWindowID)] = [
            ("remove assigned window", true, 100),
            ("remove non-existent window", false, 999),
        ]

        for testCase in cases {
            let model = Workspaces()
            if testCase.assigned {
                model.assignWindowToVirtualSpace(testCase.windowId, 1)
            }

            model.unregisterWindowById(testCase.windowId)

            XCTAssertNil(model.getVirtualSpaceForWindow(testCase.windowId), testCase.name)
        }
    }

    func testGetWindowsInVirtualSpace() {
        let model = Workspaces()

        model.assignWindowToVirtualSpace(100, 1)
        model.assignWindowToVirtualSpace(200, 1)
        model.assignWindowToVirtualSpace(300, 2)

        XCTAssertEqual(model.getWindowsInVirtualSpace(1), [100, 200])
        XCTAssertEqual(model.getWindowsInVirtualSpace(3), [])
    }

    func testReassignWindowRemovesFromOldSpace() {
        let model = Workspaces()

        model.assignWindowToVirtualSpace(100, 1)
        model.assignWindowToVirtualSpace(200, 1)
        model.assignWindowToVirtualSpace(100, 2)

        XCTAssertEqual(model.getWindowsInVirtualSpace(1), [200])
        XCTAssertEqual(model.getWindowsInVirtualSpace(2), [100])
    }

    func testReassignWindowToSameSpaceIsIdempotent() {
        let model = Workspaces()

        model.assignWindowToVirtualSpace(100, 1)
        model.assignWindowToVirtualSpace(200, 1)
        model.assignWindowToVirtualSpace(100, 1)

        XCTAssertEqual(model.getWindowsInVirtualSpace(1), [100, 200])
    }

    func testRemoveWindowFromSpaceWithMultipleWindows() {
        let model = Workspaces()

        model.assignWindowToVirtualSpace(100, 1)
        model.assignWindowToVirtualSpace(200, 1)
        model.assignWindowToVirtualSpace(300, 1)
        model.unregisterWindowById(200)

        let windows = model.getWindowsInVirtualSpace(1)

        XCTAssertEqual(windows.count, 2)
        XCTAssertFalse(windows.contains(200))
        XCTAssertTrue(windows.contains(100))
        XCTAssertTrue(windows.contains(300))
    }

    func testRemoveLastWindowLeavesSpaceEmpty() {
        let model = Workspaces()

        model.assignWindowToVirtualSpace(100, 1)
        model.unregisterWindowById(100)

        XCTAssertEqual(model.getWindowsInVirtualSpace(1).count, 0)
    }

    func testRemoveWindowCleansUpFocusedWindowReference() {
        let model = Workspaces()

        model.assignWindowToVirtualSpace(100, 1)
        model.saveFocusedWindowInVirtualSpace(1, 100)

        XCTAssertEqual(model.getFocusedWindowForVirtualSpace(1), 100)

        model.unregisterWindowById(100)

        XCTAssertNil(model.getFocusedWindowForVirtualSpace(1))
    }

    func testRemoveWindowDoesNotAffectFocusedWindowInOtherSpaces() {
        let model = Workspaces()

        model.assignWindowToVirtualSpace(100, 1)
        model.assignWindowToVirtualSpace(200, 2)
        model.saveFocusedWindowInVirtualSpace(1, 100)
        model.saveFocusedWindowInVirtualSpace(2, 200)

        model.unregisterWindowById(100)

        XCTAssertNil(model.getFocusedWindowForVirtualSpace(1))
        XCTAssertEqual(model.getFocusedWindowForVirtualSpace(2), 200)
    }

    func testFocusHistoryMaintainsOrder() {
        let model = Workspaces()

        model.assignWindowToVirtualSpace(100, 1)
        model.assignWindowToVirtualSpace(200, 1)
        model.assignWindowToVirtualSpace(300, 1)

        model.saveFocusedWindowInVirtualSpace(1, 100)
        model.saveFocusedWindowInVirtualSpace(1, 200)
        model.saveFocusedWindowInVirtualSpace(1, 300)

        XCTAssertEqual(model.getFocusedWindowForVirtualSpace(1), 300)

        model.unregisterWindowById(300)
        XCTAssertEqual(model.getFocusedWindowForVirtualSpace(1), 200)

        model.unregisterWindowById(200)
        XCTAssertEqual(model.getFocusedWindowForVirtualSpace(1), 100)
    }

    func testFocusHistoryNoDuplicates() {
        let model = Workspaces()

        model.assignWindowToVirtualSpace(100, 1)
        model.assignWindowToVirtualSpace(200, 1)

        model.saveFocusedWindowInVirtualSpace(1, 100)
        model.saveFocusedWindowInVirtualSpace(1, 200)
        model.saveFocusedWindowInVirtualSpace(1, 100)

        XCTAssertEqual(model.getFocusedWindowForVirtualSpace(1), 100)

        model.unregisterWindowById(100)
        XCTAssertEqual(model.getFocusedWindowForVirtualSpace(1), 200)
    }

    func testCategorizeWindowsForTransition() {
        let cases: [(name: String, assignments: [(window: CGWindowID, space: Int)], target: Int, toActive: [CGWindowID], toStorage: [CGWindowID])] = [
            ("no windows", [], 2, [], []),
            ("only target space windows", [(100, 2), (200, 2)], 2, [100, 200], []),
            ("only current space windows", [(100, 1), (200, 1)], 2, [], [100, 200]),
            ("windows in both spaces", [(100, 1), (200, 2), (300, 1)], 2, [200], [100, 300]),
            ("windows in other spaces go to storage", [(100, 3), (200, 4)], 2, [], [100, 200]),
            (
                "target, current and other spaces",
                [(100, 1), (200, 2), (300, 3), (400, 1)],
                2,
                [200],
                [100, 300, 400]
            ),
            ("target equals current space", [(100, 1), (200, 1), (300, 2)], 1, [100, 200], [300]),
        ]

        for testCase in cases {
            let model = Workspaces()
            for assignment in testCase.assignments {
                model.assignWindowToVirtualSpace(assignment.window, assignment.space)
            }

            let result = model.categorizeWindowsForTransition(testCase.target)

            XCTAssertEqual(result.toActive.count, testCase.toActive.count, testCase.name)
            for windowId in testCase.toActive {
                XCTAssertTrue(result.toActive.contains(windowId), testCase.name)
            }
            XCTAssertEqual(result.toStorage.count, testCase.toStorage.count, testCase.name)
            for windowId in testCase.toStorage {
                XCTAssertTrue(result.toStorage.contains(windowId), testCase.name)
            }
        }
    }

    func testAssignWindowWithNilWindowId() {
        let model = Workspaces()

        model.assignWindowToVirtualSpace(nil, 1)

        XCTAssertEqual(model.getWindowsInVirtualSpace(1).count, 0)
    }

    func testAssignWindowWithNilVirtualSpace() {
        let model = Workspaces()

        model.assignWindowToVirtualSpace(100, nil)

        XCTAssertNil(model.getVirtualSpaceForWindow(100))
    }

    func testAssignWindowToSpaceWithSingleWindow() {
        let model = Workspaces()
        let window = makeWindow(100, appName: "Safari")

        model.assignWindowToSpace(window, 1)

        XCTAssertEqual(model.getVirtualSpaceForWindow(100), 1)
        XCTAssertEqual(model.getFocusedWindowForVirtualSpace(1), 100)
    }

    func testAssignWindowToSpaceWithTabbedWindows() {
        let model = Workspaces()
        let window1 = makeWindow(100, tabCount: 2, appName: "Safari")
        let window2 = makeWindow(200, tabCount: 2, appName: "Safari")

        model.assignWindowToSpace(window1, 1)
        model.assignWindowToSpace(window2, 2)

        XCTAssertEqual(model.getVirtualSpaceForWindow(100), 2)
        XCTAssertEqual(model.getVirtualSpaceForWindow(200), 2)
        XCTAssertEqual(model.getFocusedWindowForVirtualSpace(2), 200)
    }

    func testAssignWindowToSpaceClearsFocusedWindowAndVirtualSpaceEntry() {
        let model = Workspaces()
        let window = makeWindow(100)

        model.assignWindowToSpace(window, 1)
        XCTAssertEqual(model.getVirtualSpaceForWindow(window.id), 1)

        model.assignWindowToSpace(window, 2)
        XCTAssertEqual(model.getFocusedWindowForVirtualSpace(2), window.id)
        XCTAssertNil(model.getFocusedWindowForVirtualSpace(1))
        XCTAssertEqual(model.getVirtualSpaceForWindow(window.id), 2)
    }

    func testMoveWindowToVirtualSpaceMovesRegisteredWindow() {
        let model = Workspaces()
        let window = makeWindow(100)

        model.assignWindowToSpace(window, 1)
        XCTAssertEqual(model.getVirtualSpaceForWindow(100), 1)

        model.moveWindowToVirtualSpace(100, 2)

        XCTAssertEqual(model.getVirtualSpaceForWindow(100), 2)
        XCTAssertEqual(model.getFocusedWindowForVirtualSpace(2), 100)
        XCTAssertEqual(model.getWindowsInVirtualSpace(1).count, 0)
        XCTAssertEqual(model.getWindowsInVirtualSpace(2).count, 1)
    }

    func testMoveWindowToVirtualSpaceMovesTabGroup() {
        let model = Workspaces()
        let window1 = makeWindow(100, tabCount: 2, appName: "Safari")
        let window2 = makeWindow(200, tabCount: 2, appName: "Safari")

        model.assignWindowToSpace(window1, 1)
        model.assignWindowToSpace(window2, 1)

        XCTAssertEqual(model.getVirtualSpaceForWindow(100), 1)
        XCTAssertEqual(model.getVirtualSpaceForWindow(200), 1)

        model.moveWindowToVirtualSpace(100, 3)

        XCTAssertEqual(model.getVirtualSpaceForWindow(100), 3)
        XCTAssertEqual(model.getVirtualSpaceForWindow(200), 3)
        XCTAssertEqual(model.getWindowsInVirtualSpace(1).count, 0)
        XCTAssertEqual(model.getWindowsInVirtualSpace(3).count, 2)
    }

    func testTerminalAppTabsWithSlightlyDifferentYCoordinatesAreGroupedTogether() {
        let model = Workspaces()
        let window1 = makeWindow(3426, tabCount: 1, frame: CGRect(x: 155, y: 30, width: 748, height: 879), appName: "Terminal")
        let window2 = makeWindow(3459, tabCount: 2, frame: CGRect(x: 155, y: 21, width: 748, height: 879), appName: "Terminal")

        model.assignWindowToSpace(window1, 1)
        model.assignWindowToSpace(window2, 2)

        let tabGroup1 = model.getTabGroupForWindow(3426)
        let tabGroup2 = model.getTabGroupForWindow(3459)

        XCTAssertNotNil(tabGroup1)
        XCTAssertNotNil(tabGroup2)
        XCTAssertEqual(tabGroup1?.count, 2)
        XCTAssertEqual(tabGroup1.map(Set.init), tabGroup2.map(Set.init))
        XCTAssertTrue(tabGroup1?.contains(3426) ?? false)
        XCTAssertTrue(tabGroup1?.contains(3459) ?? false)
        XCTAssertEqual(model.getVirtualSpaceForWindow(3426), model.getVirtualSpaceForWindow(3459))
    }

    func testUnregisterWindowByIdWithSingleWindow() {
        let model = Workspaces()
        let window = makeWindow(100)

        model.assignWindowToSpace(window, 1)
        XCTAssertNotNil(model.getTabGroupForWindow(100))

        model.unregisterWindowById(100)

        XCTAssertNil(model.getTabGroupForWindow(100))
    }

    func testUnregisterWindowByIdFromTabGroupWithRemainingWindows() {
        let model = Workspaces()
        let window1 = makeWindow(100, tabCount: 2, appName: "Safari")
        let window2 = makeWindow(200, tabCount: 2, appName: "Safari")

        model.assignWindowToSpace(window1, 1)
        model.assignWindowToSpace(window2, 1)

        let tabGroupBefore = model.getTabGroupForWindow(100)
        XCTAssertNotNil(tabGroupBefore)
        XCTAssertEqual(tabGroupBefore?.count, 2)

        model.unregisterWindowById(100)

        XCTAssertNil(model.getTabGroupForWindow(100))

        let tabGroupAfter = model.getTabGroupForWindow(200)
        XCTAssertNotNil(tabGroupAfter)
        XCTAssertEqual(tabGroupAfter?.count, 1)
        XCTAssertTrue(tabGroupAfter?.contains(200) ?? false)
        XCTAssertFalse(tabGroupAfter?.contains(100) ?? false)
    }

    func testUnregisterWindowByIdRemovesEmptyTabGroup() {
        let model = Workspaces()
        let window = makeWindow(100, tabCount: 2, appName: "Safari")

        model.assignWindowToSpace(window, 1)

        XCTAssertNotNil(model.getTabGroupForWindow(100))

        model.unregisterWindowById(100)

        XCTAssertNil(model.getTabGroupForWindow(100))
    }

    func testUnregisterWindowByIdWithNonExistentWindow() {
        let model = Workspaces()

        model.unregisterWindowById(999)

        XCTAssertNil(model.getTabGroupForWindow(999))
    }

    func testEligibleWindowToBeFocused() {
        let cases: [(name: String, setup: (Workspaces) -> Void, expectedWindowId: CGWindowID?, expectedFocusedWindowId: CGWindowID?)] = [
            (
                "returns saved focused window when using assignWindowToSpace flow",
                { model in
                    model.assignWindowToSpace(self.makeWindow(46), 1)
                    model.assignWindowToSpace(self.makeWindow(1375), 1)
                    model.saveFocusedWindowInVirtualSpace(1, 1375)
                },
                1375,
                1375
            ),
            (
                "returns saved focused window when still in current virtual space",
                { model in
                    model.assignWindowToVirtualSpace(100, 1)
                    model.assignWindowToVirtualSpace(200, 1)
                    model.saveFocusedWindowInVirtualSpace(1, 200)
                },
                200,
                200
            ),
            (
                "returns first window when no saved focus",
                { model in
                    model.assignWindowToVirtualSpace(100, 1)
                    model.assignWindowToVirtualSpace(200, 1)
                },
                100,
                100
            ),
            (
                "returns first window when saved focus is in different virtual space",
                { model in
                    model.assignWindowToVirtualSpace(100, 1)
                    model.assignWindowToVirtualSpace(200, 2)
                    model.saveFocusedWindowInVirtualSpace(1, 200)
                },
                100,
                100
            ),
            (
                "skips focus-history entries that moved to another virtual space",
                { model in
                    model.assignWindowToVirtualSpace(100, 1)
                    model.assignWindowToVirtualSpace(200, 1)
                    model.assignWindowToVirtualSpace(300, 1)
                    model.saveFocusedWindowInVirtualSpace(1, 100)
                    model.saveFocusedWindowInVirtualSpace(1, 200)
                    model.saveFocusedWindowInVirtualSpace(1, 300)
                    model.assignWindowToVirtualSpace(300, 2)
                },
                200,
                200
            ),
            ("returns nil when no windows in virtual space", { _ in }, nil, nil),
            (
                "returns nil when windows exist but in other virtual spaces",
                { model in
                    model.assignWindowToVirtualSpace(100, 2)
                    model.setCurrentVirtualSpace(1)
                },
                nil,
                nil
            ),
        ]

        for testCase in cases {
            let model = Workspaces()

            testCase.setup(model)
            model.setCurrentVirtualSpace(1)

            let windowId = model.prepareWindowToBeFocusedOnCurrentVirtualSpace()

            XCTAssertEqual(model.getFocusedWindowForVirtualSpace(1), testCase.expectedFocusedWindowId, testCase.name)
            XCTAssertEqual(windowId, testCase.expectedWindowId, testCase.name)
        }
    }
}
