import CoreGraphics
import XCTest

private let original = CGRect(x: 100, y: 100, width: 800, height: 600)
private let centered = CGRect(x: 496, y: 279, width: 800, height: 600)

final class WorkAreaTests: XCTestCase {
    private let workArea = WorkArea(display: .standard, spacing: 15)
    private let hiddenEdge = HiddenEdge(display: .standard)

    private func request(_ change: FrameChange) -> FrameRequest {
        FrameRequest(windowId: 100, change: change)
    }

    func testStepsBySpacingWithinTheVisibleFrame() {
        let dockMoved = Display(
            id: Display.standard.id,
            fullFrame: Display.standard.fullFrame,
            visibleFrame: CGRect(x: 0, y: 38, width: 1792, height: 1000)
        )
        let cases: [(name: String, workArea: WorkArea, change: FrameChange, expected: CGRect)] = [
            (
                "move stops at the top",
                WorkArea(display: .standard, spacing: 500),
                .move(.north),
                CGRect(x: 100, y: 38, width: 800, height: 600)
            ),
            (
                "resize stops at the bottom",
                WorkArea(display: dockMoved, spacing: 5000),
                .resize(.taller),
                CGRect(x: 100, y: 100, width: 800, height: 938)
            ),
        ]

        for testCase in cases {
            let (frame, outcome) = testCase.workArea.frame(request(testCase.change), from: original)

            XCTAssertEqual(frame, testCase.expected, testCase.name)
            XCTAssertEqual(outcome, .active(100), testCase.name)
        }
    }

    func testCenterPutsTheFrameInTheMiddleOfTheVisibleFrame() {
        let (frame, outcome) = workArea.frame(request(.center), from: original)

        XCTAssertEqual(frame, centered)
        XCTAssertEqual(outcome, .active(100))
    }

    func testFillingRecordsTheFrameUnlessTheWindowFills() {
        let shortOfFilled = CGRect(x: 15, y: 53, width: 1762, height: 1045)
        let west = CGRect(x: 15, y: 53, width: 873.5, height: 1052)
        let cases: [(name: String, change: FrameChange, current: CGRect, expected: (frame: CGRect, outcome: FrameOutcome))] = [
            (
                "maximize fills the visible frame inset by the spacing",
                .maximize(restoring: nil),
                original,
                (CGRect(x: 15, y: 53, width: 1762, height: 1052), .filled(100, from: original))
            ),
            (
                "tile takes a half of the filled frame with the spacing as the gap",
                .tile(.west, restoring: nil),
                original,
                (west, .filled(100, from: original))
            ),
            (
                "a window short of the filled frame goes back to the frame handed in",
                .maximize(restoring: original),
                CGRect(x: 15, y: 53, width: 1762, height: 1051),
                (original, .active(100))
            ),
            (
                "a filled window with nothing to restore stays",
                .maximize(restoring: nil),
                shortOfFilled,
                (shortOfFilled, .active(100))
            ),
            (
                "a window filling another target moves on rather than restoring",
                .maximize(restoring: original),
                west,
                (CGRect(x: 15, y: 53, width: 1762, height: 1052), .filled(100, from: west))
            ),
        ]

        for testCase in cases {
            let (frame, outcome) = workArea.frame(request(testCase.change), from: testCase.current)

            XCTAssertEqual(frame, testCase.expected.frame, testCase.name)
            XCTAssertEqual(outcome, testCase.expected.outcome, testCase.name)
        }
    }

    func testAFrameWithinTheToleranceFillsTheTarget() {
        XCTAssertTrue(workArea.fills(CGRect(x: 15, y: 53, width: 1762, height: 1045), workArea.filled))
        XCTAssertFalse(workArea.fills(original, workArea.filled))
    }

    func testParkingHidesTheOnScreenFrameAndRecordsIt() {
        let known = CGRect(x: 50, y: 60, width: 640, height: 480)
        let cases: [(name: String, change: FrameChange, current: CGRect, expected: (frame: CGRect, outcome: FrameOutcome))] = [
            (
                "from the current frame",
                .park(from: nil),
                original,
                (hiddenEdge.frame(parking: original), .parked(100, from: original))
            ),
            (
                "from a known frame",
                .park(from: known),
                original,
                (hiddenEdge.frame(parking: known), .parked(100, from: known))
            ),
            (
                "from a frame at the hidden edge",
                .park(from: nil),
                hiddenEdge.frame(parking: original),
                (hiddenEdge.frame(parking: original), .parked(100, from: centered))
            ),
        ]

        for testCase in cases {
            let (frame, outcome) = workArea.frame(request(testCase.change), from: testCase.current)

            XCTAssertEqual(frame, testCase.expected.frame, testCase.name)
            XCTAssertEqual(outcome, testCase.expected.outcome, testCase.name)
        }
    }

    func testUnparkingReturnsToTheOnScreenFrame() {
        let cases: [(name: String, parkedFrom: CGRect?, expected: CGRect)] = [
            ("to the frame parked from", original, original),
            ("with no frame parked from", nil, centered),
        ]

        for testCase in cases {
            let (frame, outcome) = workArea.frame(
                request(.unpark(testCase.parkedFrom)),
                from: hiddenEdge.frame(parking: original)
            )

            XCTAssertEqual(frame, testCase.expected, testCase.name)
            XCTAssertEqual(outcome, .active(100), testCase.name)
        }
    }

    func testOnScreenReplacesAHiddenEdgeFrameWithACenteredOne() {
        XCTAssertEqual(workArea.onScreen(hiddenEdge.frame(parking: original)), centered)
        XCTAssertEqual(workArea.onScreen(original), original)
    }
}
