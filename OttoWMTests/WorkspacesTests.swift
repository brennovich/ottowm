import CoreGraphics
import XCTest

final class WorkspacesTests: XCTestCase {
    func testCurrentWorkspaceStartsAtOne() {
        XCTAssertEqual(Workspaces().currentWorkspace, 1)
    }

    func testWindowAssignment() {
        let cases: [(name: String, assignments: [(window: CGWindowID, workspace: Int)], expected: [(window: CGWindowID, workspace: Int)])] = [
            ("assign single window", [(100, 1)], [(100, 1)]),
            (
                "multiple windows to same workspace",
                [(100, 1), (200, 1), (300, 2)],
                [(100, 1), (200, 1), (300, 2)]
            ),
            ("reassign window to different workspace", [(100, 1), (100, 2)], [(100, 2)]),
        ]

        for testCase in cases {
            let model = Workspaces()
            for assignment in testCase.assignments {
                model.assignWindowToWorkspace(makeSnapshot(assignment.window), assignment.workspace)
            }

            for assertion in testCase.expected {
                XCTAssertEqual(
                    model.workspace(for: assertion.window),
                    assertion.workspace,
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
                model.assignWindowToWorkspace(makeSnapshot(testCase.windowId), 1)
            }

            model.unregisterWindowById(testCase.windowId)

            XCTAssertNil(model.workspace(for: testCase.windowId), testCase.name)
        }
    }

    func testGetWindowsInWorkspace() {
        let model = Workspaces()

        model.assignWindowToWorkspace(makeSnapshot(100), 1)
        model.assignWindowToWorkspace(makeSnapshot(200), 1)
        model.assignWindowToWorkspace(makeSnapshot(300), 2)

        XCTAssertEqual(model.windowIds(in: 1), [100, 200])
        XCTAssertEqual(model.windowIds(in: 3), [])
    }

    func testReassignWindowRemovesFromOldWorkspace() {
        let model = Workspaces()

        model.assignWindowToWorkspace(makeSnapshot(100), 1)
        model.assignWindowToWorkspace(makeSnapshot(200), 1)
        model.assignWindowToWorkspace(makeSnapshot(100), 2)

        XCTAssertEqual(model.windowIds(in: 1), [200])
        XCTAssertEqual(model.windowIds(in: 2), [100])
    }

    func testReassignWindowToSameWorkspaceIsIdempotent() {
        let model = Workspaces()

        model.assignWindowToWorkspace(makeSnapshot(100), 1)
        model.assignWindowToWorkspace(makeSnapshot(200), 1)
        model.assignWindowToWorkspace(makeSnapshot(100), 1)

        XCTAssertEqual(model.windowIds(in: 1), [100, 200])
    }

    func testRemoveWindowFromWorkspaceWithMultipleWindows() {
        let model = Workspaces()

        model.assignWindowToWorkspace(makeSnapshot(100), 1)
        model.assignWindowToWorkspace(makeSnapshot(200), 1)
        model.assignWindowToWorkspace(makeSnapshot(300), 1)
        model.unregisterWindowById(200)

        let windows = model.windowIds(in: 1)

        XCTAssertEqual(windows.count, 2)
        XCTAssertFalse(windows.contains(200))
        XCTAssertTrue(windows.contains(100))
        XCTAssertTrue(windows.contains(300))
    }

    func testRemoveLastWindowLeavesWorkspaceEmpty() {
        let model = Workspaces()

        model.assignWindowToWorkspace(makeSnapshot(100), 1)
        model.unregisterWindowById(100)

        XCTAssertEqual(model.windowIds(in: 1).count, 0)
    }

    func testRemoveWindowDoesNotAffectFocusedWindowInOtherWorkspaces() {
        let model = Workspaces()

        model.assignWindowToWorkspace(makeSnapshot(100), 1)
        model.assignWindowToWorkspace(makeSnapshot(200), 2)
        model.saveFocusedWindowInWorkspace(1, 100)
        model.saveFocusedWindowInWorkspace(2, 200)

        model.unregisterWindowById(100)

        XCTAssertNil(model.nextWindowToFocus())

        _ = model.switchTo(2, leavingFocusOn: nil)
        XCTAssertEqual(model.nextWindowToFocus(), 200)
    }

    func testFocusHistoryMaintainsOrder() {
        let model = Workspaces()

        model.assignWindowToWorkspace(makeSnapshot(100), 1)
        model.assignWindowToWorkspace(makeSnapshot(200), 1)
        model.assignWindowToWorkspace(makeSnapshot(300), 1)

        model.saveFocusedWindowInWorkspace(1, 100)
        model.saveFocusedWindowInWorkspace(1, 200)
        model.saveFocusedWindowInWorkspace(1, 300)

        XCTAssertEqual(model.nextWindowToFocus(), 300)

        model.unregisterWindowById(300)
        XCTAssertEqual(model.nextWindowToFocus(), 200)

        model.unregisterWindowById(200)
        XCTAssertEqual(model.nextWindowToFocus(), 100)
    }

    func testFocusHistoryNoDuplicates() {
        let model = Workspaces()

        model.assignWindowToWorkspace(makeSnapshot(100), 1)
        model.assignWindowToWorkspace(makeSnapshot(200), 1)

        model.saveFocusedWindowInWorkspace(1, 100)
        model.saveFocusedWindowInWorkspace(1, 200)
        model.saveFocusedWindowInWorkspace(1, 100)

        XCTAssertEqual(model.nextWindowToFocus(), 100)

        model.unregisterWindowById(100)
        XCTAssertEqual(model.nextWindowToFocus(), 200)
    }

    func testSwitchTo() {
        let cases: [(name: String, assignments: [(window: CGWindowID, workspace: Int)], target: Int, toActive: [CGWindowID], toStorage: [CGWindowID])] = [
            ("no windows", [], 2, [], []),
            ("only target workspace windows", [(100, 2), (200, 2)], 2, [100, 200], []),
            ("only current workspace windows", [(100, 1), (200, 1)], 2, [], [100, 200]),
            ("windows in both workspaces", [(100, 1), (200, 2), (300, 1)], 2, [200], [100, 300]),
            ("windows in other workspaces go to storage", [(100, 3), (200, 4)], 2, [], [100, 200]),
            (
                "target, current and other workspaces",
                [(100, 1), (200, 2), (300, 3), (400, 1)],
                2,
                [200],
                [100, 300, 400]
            ),
            ("target equals current workspace places nothing", [(100, 1), (200, 1), (300, 2)], 1, [], []),
        ]

        for testCase in cases {
            let model = Workspaces()
            for assignment in testCase.assignments {
                model.assignWindowToWorkspace(makeSnapshot(assignment.window), assignment.workspace)
            }

            let result = model.switchTo(testCase.target, leavingFocusOn: nil)

            XCTAssertEqual(model.currentWorkspace, testCase.target, testCase.name)
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

    func testSwitchToSavesFocusInTheWorkspaceBeingLeft() {
        let model = Workspaces()

        model.assignWindowToWorkspace(makeSnapshot(100), 1)
        model.assignWindowToWorkspace(makeSnapshot(200), 1)

        _ = model.switchTo(2, leavingFocusOn: 100)
        _ = model.switchTo(1, leavingFocusOn: nil)

        XCTAssertEqual(model.nextWindowToFocus(), 100)
    }

    func testAllWindowIds() {
        let cases: [(name: String, assignments: [(window: CGWindowID, workspace: Int)], unregister: [CGWindowID], expected: Set<CGWindowID>)] = [
            ("empty model", [], [], []),
            ("single window", [(100, 1)], [], [100]),
            ("windows across workspaces", [(100, 1), (200, 2), (300, 3)], [], [100, 200, 300]),
            ("unregistered window is excluded", [(100, 1), (200, 1)], [100], [200]),
        ]

        for testCase in cases {
            let model = Workspaces()
            for assignment in testCase.assignments {
                model.assignWindowToWorkspace(makeSnapshot(assignment.window), assignment.workspace)
            }
            for windowId in testCase.unregister {
                model.unregisterWindowById(windowId)
            }

            XCTAssertEqual(model.allWindowIds, testCase.expected, testCase.name)
        }
    }

    func testAssignWindowToWorkspaceWithSingleWindow() {
        let model = Workspaces()
        let window = makeSnapshot(100, appName: "Safari")

        model.assignWindowToWorkspace(window, 1)

        XCTAssertEqual(model.workspace(for: 100), 1)
        XCTAssertEqual(model.nextWindowToFocus(), 100)
    }

    func testAssignWindowToWorkspaceWithTabbedWindows() {
        let model = Workspaces()
        let window1 = makeSnapshot(100, appName: "Safari", tabCount: 2)
        let window2 = makeSnapshot(200, appName: "Safari", tabCount: 2)

        model.assignWindowToWorkspace(window1, 1)
        model.assignWindowToWorkspace(window2, 2)

        XCTAssertEqual(model.workspace(for: 100), 2)
        XCTAssertEqual(model.workspace(for: 200), 2)

        _ = model.switchTo(2, leavingFocusOn: nil)
        XCTAssertEqual(model.nextWindowToFocus(), 200)
    }

    func testAssignWindowToWorkspaceClearsFocusedWindowAndWorkspaceEntry() {
        let model = Workspaces()
        let window = makeSnapshot(100)

        model.assignWindowToWorkspace(window, 1)
        XCTAssertEqual(model.workspace(for: window.id), 1)

        model.assignWindowToWorkspace(window, 2)
        XCTAssertEqual(model.workspace(for: window.id), 2)
        XCTAssertNil(model.nextWindowToFocus())

        _ = model.switchTo(2, leavingFocusOn: nil)
        XCTAssertEqual(model.nextWindowToFocus(), window.id)
    }

    func testMoveWindowToWorkspaceMovesRegisteredWindow() {
        let model = Workspaces()
        let window = makeSnapshot(100)

        model.assignWindowToWorkspace(window, 1)
        XCTAssertEqual(model.workspace(for: 100), 1)

        model.moveWindowToWorkspace(100, 2)

        XCTAssertEqual(model.workspace(for: 100), 2)
        XCTAssertEqual(model.windowIds(in: 1).count, 0)
        XCTAssertEqual(model.windowIds(in: 2).count, 1)

        _ = model.switchTo(2, leavingFocusOn: nil)
        XCTAssertEqual(model.nextWindowToFocus(), 100)
    }

    func testMoveWindowToWorkspaceMovesTabGroup() {
        let model = Workspaces()
        let window1 = makeSnapshot(100, appName: "Safari", tabCount: 2)
        let window2 = makeSnapshot(200, appName: "Safari", tabCount: 2)

        model.assignWindowToWorkspace(window1, 1)
        model.assignWindowToWorkspace(window2, 1)

        XCTAssertEqual(model.workspace(for: 100), 1)
        XCTAssertEqual(model.workspace(for: 200), 1)

        model.moveWindowToWorkspace(100, 3)

        XCTAssertEqual(model.workspace(for: 100), 3)
        XCTAssertEqual(model.workspace(for: 200), 3)
        XCTAssertEqual(model.windowIds(in: 1).count, 0)
        XCTAssertEqual(model.windowIds(in: 3).count, 2)
    }

    func testUnregisteringATabLeavesItsSiblingsInPlaceAndFocused() {
        let model = Workspaces()

        model.assignWindowToWorkspace(makeSnapshot(100, appName: "Safari", tabCount: 2), 1)
        model.assignWindowToWorkspace(makeSnapshot(200, appName: "Safari", tabCount: 2), 1)
        model.assignWindowToWorkspace(makeSnapshot(300), 1)
        model.saveFocusedWindowInWorkspace(1, 300)

        model.unregisterWindowById(100)

        XCTAssertNil(model.workspace(for: 100))
        XCTAssertEqual(model.workspace(for: 200), 1)
        XCTAssertEqual(model.nextWindowToFocus(), 200)
    }

    func testEligibleWindowToBeFocused() {
        let cases: [(name: String, setup: (Workspaces) -> Void, expectedWindowId: CGWindowID?)] = [
            (
                "returns saved focused window when still in current workspace",
                { model in
                    model.assignWindowToWorkspace(makeSnapshot(100), 1)
                    model.assignWindowToWorkspace(makeSnapshot(200), 1)
                    model.saveFocusedWindowInWorkspace(1, 200)
                },
                200
            ),
            (
                "skips focus-history entries belonging to another workspace",
                { model in
                    model.assignWindowToWorkspace(makeSnapshot(100), 1)
                    model.assignWindowToWorkspace(makeSnapshot(200), 2)
                    model.saveFocusedWindowInWorkspace(1, 200)
                },
                100
            ),
            (
                "picks the next most recent window after the focused one moves away",
                { model in
                    model.assignWindowToWorkspace(makeSnapshot(100), 1)
                    model.assignWindowToWorkspace(makeSnapshot(200), 1)
                    model.assignWindowToWorkspace(makeSnapshot(300), 1)
                    model.saveFocusedWindowInWorkspace(1, 100)
                    model.saveFocusedWindowInWorkspace(1, 200)
                    model.saveFocusedWindowInWorkspace(1, 300)
                    model.moveWindowToWorkspace(300, 2)
                },
                200
            ),
            (
                "falls back to the first window when the workspace has no focus history",
                { model in
                    model.assignWindowToWorkspace(makeSnapshot(100, appName: "Safari", tabCount: 2), 2)
                    model.assignWindowToWorkspace(makeSnapshot(200, appName: "Safari", tabCount: 2), 2)
                    _ = model.switchTo(2, leavingFocusOn: nil)
                    model.moveWindowToWorkspace(100, 1)
                    model.unregisterWindowById(100)
                },
                200
            ),
            ("returns nil when no windows in workspace", { _ in }, nil),
            (
                "returns nil when windows exist but in other workspaces",
                { model in
                    model.assignWindowToWorkspace(makeSnapshot(100), 2)
                },
                nil
            ),
        ]

        for testCase in cases {
            let model = Workspaces()

            testCase.setup(model)
            _ = model.switchTo(1, leavingFocusOn: nil)

            let windowId = model.nextWindowToFocus()

            XCTAssertEqual(windowId, testCase.expectedWindowId, testCase.name)
        }
    }
}
