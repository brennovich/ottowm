import XCTest

final class HiddenEdgeTests: XCTestCase {
    private let hiddenEdge = HiddenEdge(screen: StubScreen.standard)

    func testParkingPinsOriginToBottomRightNubKeepingSize() {
        let hidden = hiddenEdge.frame(parking: CGRect(x: 100, y: 100, width: 800, height: 600))

        XCTAssertEqual(hidden, CGRect(x: 1791, y: 1119, width: 800, height: 600))
    }

    func testHolds() {
        let cases: [(name: String, x: CGFloat, expected: Bool)] = [
            ("pinned at the nub", 1791, true),
            ("just inside the detection margin", 1781, true),
            ("just outside the detection margin", 1780, false),
            ("normal window", 100, false),
        ]

        for testCase in cases {
            let frame = CGRect(x: testCase.x, y: 100, width: 800, height: 600)
            XCTAssertEqual(hiddenEdge.holds(frame), testCase.expected, testCase.name)
        }
    }
}
