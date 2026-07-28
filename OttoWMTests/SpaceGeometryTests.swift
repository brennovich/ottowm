import XCTest

final class SpaceGeometryTests: XCTestCase {
    private let screen = StubScreen.standard

    func testHiddenFramePinsOriginToBottomRightNubKeepingSize() {
        let hidden = hiddenFrame(for: CGRect(x: 100, y: 100, width: 800, height: 600), on: screen)

        XCTAssertEqual(hidden, CGRect(x: 1791, y: 1119, width: 800, height: 600))
    }

    func testIsStuckAtHiddenEdge() {
        let cases: [(name: String, x: CGFloat, expected: Bool)] = [
            ("pinned at the nub", 1791, true),
            ("just inside the detection margin", 1781, true),
            ("just outside the detection margin", 1780, false),
            ("normal window", 100, false),
        ]

        for testCase in cases {
            let frame = CGRect(x: testCase.x, y: 100, width: 800, height: 600)
            XCTAssertEqual(isStuckAtHiddenEdge(frame, on: screen), testCase.expected, testCase.name)
        }
    }

    func testRecoveredFrameCentersWithinVisibleFrame() {
        let recovered = recoveredFrame(
            for: CGRect(x: 1791, y: 1119, width: 800, height: 600),
            visibleFrame: screen.visibleFrame
        )

        XCTAssertEqual(recovered, CGRect(x: 496, y: 279, width: 800, height: 600))
    }

    func testRecoveredFrameClampsToVisibleFrame() {
        let recovered = recoveredFrame(
            for: CGRect(x: 1791, y: 1119, width: 2000, height: 1200),
            visibleFrame: screen.visibleFrame
        )

        XCTAssertEqual(recovered, CGRect(x: 0, y: 38, width: 1792, height: 1082))
    }
}
