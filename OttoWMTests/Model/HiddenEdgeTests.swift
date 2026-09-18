import XCTest

final class HiddenEdgeTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 100, width: 800, height: 600)

    func testParkingPinsTheOriginToTheBottomRightOfTheDisplayKeepingTheSize() {
        let cases: [(name: String, display: Display, expected: CGPoint)] = [
            ("built-in", .standard, CGPoint(x: 1791, y: 1119)),
            ("external", .external, CGPoint(x: 2559, y: 1439)),
        ]

        for testCase in cases {
            let hidden = HiddenEdge(display: testCase.display).frame(parking: frame)
            XCTAssertEqual(hidden, CGRect(origin: testCase.expected, size: frame.size), testCase.name)
        }
    }

    func testHolds() {
        let cases: [(name: String, display: Display, x: CGFloat, expected: Bool)] = [
            ("at the hidden edge", .standard, 1791, true),
            ("just inside the detection margin", .standard, 1781, true),
            ("just outside the detection margin", .standard, 1780, false),
            ("normal window", .standard, 100, false),
            ("at the hidden edge of a smaller display", .external, 1791, false),
        ]

        for testCase in cases {
            let frame = CGRect(x: testCase.x, y: 100, width: 800, height: 600)
            XCTAssertEqual(HiddenEdge(display: testCase.display).holds(frame), testCase.expected, testCase.name)
        }
    }
}
