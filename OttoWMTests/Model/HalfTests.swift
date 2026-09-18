import CoreGraphics
import XCTest

final class HalfTests: XCTestCase {
    func testEachHalfTakesOneSideOfTheBoundsWithTheGapBetweenThem() {
        let bounds = CGRect(x: 10, y: 20, width: 400, height: 300)

        let cases: [(direction: Direction, frame: CGRect)] = [
            (.west, CGRect(x: 10, y: 20, width: 190, height: 300)),
            (.east, CGRect(x: 220, y: 20, width: 190, height: 300)),
            (.north, CGRect(x: 10, y: 20, width: 400, height: 140)),
            (.south, CGRect(x: 10, y: 180, width: 400, height: 140)),
        ]

        for (direction, expected) in cases {
            XCTAssertEqual(
                Half(direction: direction).frame(within: bounds, gap: 20),
                expected,
                direction.rawValue
            )
        }
    }
}
