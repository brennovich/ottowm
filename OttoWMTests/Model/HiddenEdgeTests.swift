import XCTest

final class HiddenEdgeTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
    private var parkingLeft: Display {
        var display = Display.standard
        display.parkingCorner = .bottomLeft
        return display
    }

    func testParkingPinsTheWindowToTheParkingCornerOfTheDisplayKeepingTheSize() {
        let cases: [(name: String, display: Display, expected: CGPoint)] = [
            ("built-in", .standard, CGPoint(x: 1791, y: 1119)),
            ("external", .external, CGPoint(x: 2559, y: 1439)),
            ("bottom left", parkingLeft, CGPoint(x: -799, y: 1119)),
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
            ("at the bottom left hidden edge", parkingLeft, -799, true),
            ("just inside the bottom left detection margin", parkingLeft, -789, true),
            ("just outside the bottom left detection margin", parkingLeft, -788, false),
        ]

        for testCase in cases {
            let frame = CGRect(x: testCase.x, y: 100, width: 800, height: 600)
            XCTAssertEqual(HiddenEdge(display: testCase.display).holds(frame), testCase.expected, testCase.name)
        }
    }
}
