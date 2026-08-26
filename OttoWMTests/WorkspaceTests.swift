import CoreGraphics
import XCTest

final class WorkspaceTests: XCTestCase {
    private enum Step {
        case add(CGWindowID)
        case remove(CGWindowID)
        case recordFocus(CGWindowID)
    }

    private func makeWorkspace(_ steps: [Step]) -> Workspace {
        var workspace = Workspace()
        for step in steps {
            switch step {
            case let .add(windowId): workspace.add(windowId)
            case let .remove(windowId): workspace.remove(windowId)
            case let .recordFocus(windowId): workspace.recordFocus(on: windowId)
            }
        }
        return workspace
    }

    func testWindowIds() {
        let cases: [(name: String, steps: [Step], windowIds: [CGWindowID])] = [
            ("no windows", [], []),
            ("added windows keep their order", [.add(100), .add(200)], [100, 200]),
            ("a removed window is dropped", [.add(100), .add(200), .remove(100)], [200]),
            ("removing a window it does not hold changes nothing", [.add(100), .remove(200)], [100]),
        ]

        for testCase in cases {
            XCTAssertEqual(makeWorkspace(testCase.steps).windowIds, testCase.windowIds, testCase.name)
        }
    }

    func testNextWindowToFocus() {
        let cases: [(name: String, steps: [Step], nextWindowToFocus: CGWindowID?)] = [
            ("no windows", [], nil),
            ("no focus history falls back to the first window", [.add(100), .add(200)], 100),
            ("the most recently focused window", [.add(100), .add(200), .recordFocus(100), .recordFocus(200)], 200),
            (
                "refocusing an older window moves it to the front",
                [.add(100), .add(200), .recordFocus(100), .recordFocus(200), .recordFocus(100)],
                100
            ),
            (
                "a removed window is dropped from the focus history",
                [.add(100), .add(200), .recordFocus(100), .recordFocus(200), .remove(200)],
                100
            ),
            (
                "a window added back does not regain its place in the focus history",
                [.add(100), .add(200), .recordFocus(100), .recordFocus(200), .remove(200), .add(200)],
                100
            ),
            ("focus on a window the workspace does not hold is ignored", [.add(100), .recordFocus(200)], 100),
        ]

        for testCase in cases {
            XCTAssertEqual(makeWorkspace(testCase.steps).nextWindowToFocus, testCase.nextWindowToFocus, testCase.name)
        }
    }
}
