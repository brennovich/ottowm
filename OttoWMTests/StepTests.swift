import CoreGraphics
import XCTest

final class StepTests: XCTestCase {
    private let bounds = StubScreen.standard.visibleFrame
    private let frame = CGRect(x: 800, y: 500, width: 400, height: 300)

    func testMovesAlongTheAxisTheDirectionTravels() {
        let cases: [(name: String, direction: Direction, expected: CGRect)] = [
            ("north", .north, CGRect(x: 800, y: 485, width: 400, height: 300)),
            ("south", .south, CGRect(x: 800, y: 515, width: 400, height: 300)),
            ("west", .west, CGRect(x: 785, y: 500, width: 400, height: 300)),
            ("east", .east, CGRect(x: 815, y: 500, width: 400, height: 300)),
        ]

        for testCase in cases {
            let step = Step(direction: testCase.direction, points: 15)

            XCTAssertEqual(step.frame(moving: frame, within: bounds), testCase.expected, testCase.name)
        }
    }

    func testStopsAtTheEdgeItTravelsTowards() {
        let cases: [(name: String, direction: Direction, frame: CGRect, expected: CGRect)] = [
            (
                "north stops at the top",
                .north,
                CGRect(x: 800, y: 48, width: 400, height: 300),
                CGRect(x: 800, y: 38, width: 400, height: 300)
            ),
            (
                "south stops at the bottom",
                .south,
                CGRect(x: 800, y: 810, width: 400, height: 300),
                CGRect(x: 800, y: 820, width: 400, height: 300)
            ),
            (
                "west stops at the left",
                .west,
                CGRect(x: 10, y: 500, width: 400, height: 300),
                CGRect(x: 0, y: 500, width: 400, height: 300)
            ),
            (
                "east stops at the right",
                .east,
                CGRect(x: 1382, y: 500, width: 400, height: 300),
                CGRect(x: 1392, y: 500, width: 400, height: 300)
            ),
        ]

        for testCase in cases {
            let step = Step(direction: testCase.direction, points: 100)

            XCTAssertEqual(step.frame(moving: testCase.frame, within: bounds), testCase.expected, testCase.name)
        }
    }

    func testWindowPastTheEdgeStaysWhereItIs() {
        let cases: [(name: String, direction: Direction, frame: CGRect)] = [
            ("north above the top", .north, CGRect(x: 800, y: -50, width: 400, height: 300)),
            ("south below the bottom", .south, CGRect(x: 800, y: 1000, width: 400, height: 300)),
            ("west left of the left", .west, CGRect(x: -50, y: 500, width: 400, height: 300)),
            ("east right of the right", .east, CGRect(x: 1500, y: 500, width: 400, height: 300)),
        ]

        for testCase in cases {
            let step = Step(direction: testCase.direction, points: 15)

            XCTAssertEqual(step.frame(moving: testCase.frame, within: bounds), testCase.frame, testCase.name)
        }
    }

    func testWindowLargerThanTheBoundsDoesNotMoveAlongThatAxis() {
        let wide = CGRect(x: 0, y: 500, width: 2000, height: 300)

        for direction in [Direction.east, .west] {
            let step = Step(direction: direction, points: 15)

            XCTAssertEqual(step.frame(moving: wide, within: bounds), wide, direction.rawValue)
        }
    }

    func testTheAxisTheMoveDoesNotTravelIsLeftAlone() {
        let offScreen = CGRect(x: -300, y: 500, width: 400, height: 300)
        let step = Step(direction: .south, points: 15)

        XCTAssertEqual(step.frame(moving: offScreen, within: bounds), offScreen.offsetBy(dx: 0, dy: 15))
    }
}
