import CoreGraphics
import XCTest

final class WorkspacesTests: XCTestCase {
    private typealias Assignments = [(window: CGWindowID, workspace: Int)]

    private func makeWorkspaces(assigning assignments: Assignments) -> Workspaces {
        let model = Workspaces()
        for assignment in assignments {
            model.assign(makeSnapshot(assignment.window), to: assignment.workspace)
        }
        return model
    }

    func testCurrentWorkspaceStartsAtOne() {
        XCTAssertEqual(Workspaces().current, 1)
    }

    func testWindowAssignment() {
        let cases: [(name: String, assignments: Assignments, windowsByWorkspace: [Int: [CGWindowID]])] = [
            ("assign single window", [(100, 1)], [1: [100]]),
            ("multiple windows across workspaces", [(100, 1), (200, 1), (300, 2)], [1: [100, 200], 2: [300], 3: []]),
            ("reassign window to a different workspace", [(100, 1), (200, 1), (100, 2)], [1: [200], 2: [100]]),
            ("reassign window to the same workspace is idempotent", [(100, 1), (200, 1), (100, 1)], [1: [100, 200]]),
        ]

        for testCase in cases {
            let model = makeWorkspaces(assigning: testCase.assignments)

            for (workspace, windowIds) in testCase.windowsByWorkspace {
                XCTAssertEqual(model.windowIds(in: workspace), windowIds, testCase.name)
                for windowId in windowIds {
                    XCTAssertEqual(model.workspace(for: windowId), workspace, testCase.name)
                }
            }
        }
    }

    func testUnregisterWindow() {
        let cases: [(name: String, assignments: Assignments, unregister: CGWindowID, remaining: [CGWindowID])] = [
            ("remove the only window", [(100, 1)], 100, []),
            ("remove non-existent window", [], 999, []),
            ("remove one window among several", [(100, 1), (200, 1), (300, 1)], 200, [100, 300]),
        ]

        for testCase in cases {
            let model = makeWorkspaces(assigning: testCase.assignments)

            XCTAssertFalse(model.remove(testCase.unregister), testCase.name)

            XCTAssertNil(model.workspace(for: testCase.unregister), testCase.name)
            XCTAssertEqual(model.windowIds(in: 1), testCase.remaining, testCase.name)
        }
    }

    func testRemoveWindowDoesNotAffectFocusedWindowInOtherWorkspaces() {
        let model = makeWorkspaces(assigning: [(100, 1), (200, 2)])
        model.recordFocus(on: 100, in: 1)
        model.recordFocus(on: 200, in: 2)

        model.remove(100)

        XCTAssertNil(model.nextWindowToFocus)

        _ = model.switchTo(2, leavingFocusOn: nil)
        XCTAssertEqual(model.nextWindowToFocus, 200)
    }

    func testFocusHistoryMaintainsOrder() {
        let model = makeWorkspaces(assigning: [(100, 1), (200, 1), (300, 1)])

        model.recordFocus(on: 100, in: 1)
        model.recordFocus(on: 200, in: 1)
        model.recordFocus(on: 300, in: 1)

        XCTAssertEqual(model.nextWindowToFocus, 300)

        model.remove(300)
        XCTAssertEqual(model.nextWindowToFocus, 200)

        model.remove(200)
        XCTAssertEqual(model.nextWindowToFocus, 100)
    }

    func testFocusHistoryNoDuplicates() {
        let model = makeWorkspaces(assigning: [(100, 1), (200, 1)])

        model.recordFocus(on: 100, in: 1)
        model.recordFocus(on: 200, in: 1)
        model.recordFocus(on: 100, in: 1)

        XCTAssertEqual(model.nextWindowToFocus, 100)

        model.remove(100)
        XCTAssertEqual(model.nextWindowToFocus, 200)
    }

    func testSwitchTo() {
        typealias Placement = (toActive: Set<CGWindowID>, toStorage: Set<CGWindowID>)
        let cases: [(name: String, assignments: Assignments, target: Int, placement: Placement)] = [
            ("no windows", [], 2, ([], [])),
            ("only target workspace windows", [(100, 2), (200, 2)], 2, ([100, 200], [])),
            ("only current workspace windows", [(100, 1), (200, 1)], 2, ([], [100, 200])),
            ("windows in both workspaces", [(100, 1), (200, 2), (300, 1)], 2, ([200], [100, 300])),
            ("windows in other workspaces go to storage", [(100, 3), (200, 4)], 2, ([], [100, 200])),
            (
                "target, current and other workspaces",
                [(100, 1), (200, 2), (300, 3), (400, 1)],
                2,
                ([200], [100, 300, 400])
            ),
            ("target equals current workspace places nothing", [(100, 1), (200, 1), (300, 2)], 1, ([], [])),
        ]

        for testCase in cases {
            let model = makeWorkspaces(assigning: testCase.assignments)

            let result = model.switchTo(testCase.target, leavingFocusOn: nil)

            XCTAssertEqual(model.current, testCase.target, testCase.name)
            XCTAssertEqual(Set(result.toActive), testCase.placement.toActive, testCase.name)
            XCTAssertEqual(Set(result.toStorage), testCase.placement.toStorage, testCase.name)
        }
    }

    func testSwitchToSavesFocusInTheWorkspaceBeingLeft() {
        let model = makeWorkspaces(assigning: [(100, 1), (200, 1)])

        _ = model.switchTo(2, leavingFocusOn: 100)
        _ = model.switchTo(1, leavingFocusOn: nil)

        XCTAssertEqual(model.nextWindowToFocus, 100)
    }

    func testAllWindowIds() {
        let cases: [(name: String, assignments: Assignments, unregister: [CGWindowID], expected: Set<CGWindowID>)] = [
            ("empty model", [], [], []),
            ("single window", [(100, 1)], [], [100]),
            ("windows across workspaces", [(100, 1), (200, 2), (300, 3)], [], [100, 200, 300]),
            ("unregistered window is excluded", [(100, 1), (200, 1)], [100], [200]),
        ]

        for testCase in cases {
            let model = makeWorkspaces(assigning: testCase.assignments)
            for windowId in testCase.unregister {
                model.remove(windowId)
            }

            XCTAssertEqual(model.allWindowIds, testCase.expected, testCase.name)
        }
    }

    func testAssignWindowToWorkspaceKeepsATabGroupWhereItAlreadyIsAndReportsIt() {
        let model = Workspaces()

        XCTAssertEqual(model.assign(makeSnapshot(100, appName: "Safari"), to: 1, tabCount: 2), 1)
        XCTAssertEqual(model.assign(makeSnapshot(200, appName: "Safari"), to: 2, tabCount: 2), 1)

        XCTAssertEqual(model.workspace(for: 100), 1)
        XCTAssertEqual(model.workspace(for: 200), 1)
        XCTAssertEqual(model.nextWindowToFocus, 200)
    }

    func testAssignWindowToWorkspaceClearsFocusedWindowAndWorkspaceEntry() {
        let model = makeWorkspaces(assigning: [(100, 1)])

        model.assign(makeSnapshot(100), to: 2)

        XCTAssertEqual(model.workspace(for: 100), 2)
        XCTAssertNil(model.nextWindowToFocus)

        _ = model.switchTo(2, leavingFocusOn: nil)
        XCTAssertEqual(model.nextWindowToFocus, 100)
    }

    func testMoveWindowToWorkspaceMovesRegisteredWindow() {
        let model = makeWorkspaces(assigning: [(100, 1)])

        model.move(100, to: 2)

        XCTAssertEqual(model.workspace(for: 100), 2)
        XCTAssertEqual(model.windowIds(in: 1), [])
        XCTAssertEqual(model.windowIds(in: 2), [100])

        _ = model.switchTo(2, leavingFocusOn: nil)
        XCTAssertEqual(model.nextWindowToFocus, 100)
    }

    func testMoveWindowToWorkspaceMovesTabGroup() {
        let model = Workspaces()
        model.assign(makeSnapshot(100, appName: "Safari"), to: 1, tabCount: 2)
        model.assign(makeSnapshot(200, appName: "Safari"), to: 1, tabCount: 2)

        model.move(100, to: 3)

        XCTAssertEqual(model.workspace(for: 100), 3)
        XCTAssertEqual(model.workspace(for: 200), 3)
        XCTAssertEqual(model.windowIds(in: 1), [])
        XCTAssertEqual(model.windowIds(in: 3).count, 2)
    }

    func testUnregisteringATabLeavesItsSiblingsInPlaceAndFocused() {
        let model = Workspaces()
        model.assign(makeSnapshot(100, appName: "Safari"), to: 1, tabCount: 2)
        model.assign(makeSnapshot(200, appName: "Safari"), to: 1, tabCount: 2)
        model.assign(makeSnapshot(300), to: 1)
        model.recordFocus(on: 300, in: 1)

        XCTAssertTrue(model.remove(100))

        XCTAssertNil(model.workspace(for: 100))
        XCTAssertEqual(model.workspace(for: 200), 1)
        XCTAssertEqual(model.nextWindowToFocus, 200)
    }

    func testUnregisteringATabPromotesItsSiblingInTheGroupsOwnWorkspace() {
        let model = Workspaces()
        model.assign(makeSnapshot(100, appName: "Safari"), to: 2, tabCount: 2)
        model.assign(makeSnapshot(200, appName: "Safari"), to: 2, tabCount: 2)
        model.assign(makeSnapshot(400), to: 2)
        model.recordFocus(on: 400, in: 2)

        model.remove(100)

        _ = model.switchTo(2, leavingFocusOn: nil)
        XCTAssertEqual(model.nextWindowToFocus, 200)
    }

    func testEligibleWindowToBeFocused() {
        let cases: [(name: String, setup: (Workspaces) -> Void, expectedWindowId: CGWindowID?)] = [
            (
                "returns saved focused window when still in current workspace",
                { model in
                    model.assign(makeSnapshot(100), to: 1)
                    model.assign(makeSnapshot(200), to: 1)
                    model.recordFocus(on: 200, in: 1)
                },
                200
            ),
            (
                "skips focus-history entries belonging to another workspace",
                { model in
                    model.assign(makeSnapshot(100), to: 1)
                    model.assign(makeSnapshot(200), to: 2)
                    model.recordFocus(on: 200, in: 1)
                },
                100
            ),
            (
                "picks the next most recent window after the focused one moves away",
                { model in
                    model.assign(makeSnapshot(100), to: 1)
                    model.assign(makeSnapshot(200), to: 1)
                    model.assign(makeSnapshot(300), to: 1)
                    model.recordFocus(on: 100, in: 1)
                    model.recordFocus(on: 200, in: 1)
                    model.recordFocus(on: 300, in: 1)
                    model.move(300, to: 2)
                },
                200
            ),
            (
                "falls back to the first window when the workspace has no focus history",
                { model in
                    model.assign(makeSnapshot(100, appName: "Safari"), to: 2, tabCount: 2)
                    model.assign(makeSnapshot(200, appName: "Safari"), to: 2, tabCount: 2)
                    _ = model.switchTo(2, leavingFocusOn: nil)
                    model.move(100, to: 1)
                    model.remove(100)
                },
                200
            ),
            ("returns nil when no windows in workspace", { _ in }, nil),
            (
                "returns nil when windows exist but in other workspaces",
                { model in
                    model.assign(makeSnapshot(100), to: 2)
                },
                nil
            ),
        ]

        for testCase in cases {
            let model = Workspaces()

            testCase.setup(model)
            _ = model.switchTo(1, leavingFocusOn: nil)

            let windowId = model.nextWindowToFocus

            XCTAssertEqual(windowId, testCase.expectedWindowId, testCase.name)
        }
    }
}
