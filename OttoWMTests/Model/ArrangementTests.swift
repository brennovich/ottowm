import CoreGraphics
import XCTest

final class ArrangementTests: XCTestCase {
    func testAFrameIsOnTheDisplayHoldingItsLargerPartElseTheNearest() {
        let arrangement = Arrangement(displays: [.standard, .right])

        let cases: [(name: String, frame: CGRect, expected: Display?)] = [
            ("origin on one, larger part on the other", CGRect(x: 1791, y: 500, width: 800, height: 600), .right),
            ("on no display", CGRect(x: 1900, y: 1000, width: 800, height: 600), .right),
        ]

        for testCase in cases {
            XCTAssertEqual(arrangement.display(of: testCase.frame), testCase.expected, testCase.name)
        }
    }

    func testEachDisplayParksAtTheBottomCornerNoNeighbourCovers() {
        let leftBelowTheCorner = Display(
            id: DisplayID(rawValue: "left"),
            fullFrame: CGRect(x: -1920, y: 101, width: 1920, height: 1080),
            visibleFrame: CGRect(x: -1920, y: 126, width: 1920, height: 1055)
        )
        let cases: [(name: String, neighbours: [Display], expected: ParkingCorner)] = [
            ("no neighbour beyond the corner", [.right], .bottomRight),
            ("neighbour right, below the corner", [.rightBelowTheCorner], .bottomLeft),
            ("neighbours right and left, both below their corners", [.rightBelowTheCorner, leftBelowTheCorner], .bottomRight),
        ]

        for testCase in cases {
            let arrangement = Arrangement(displays: [.standard] + testCase.neighbours)

            XCTAssertEqual(arrangement.displays.first?.parkingCorner, testCase.expected, testCase.name)
        }
    }
}
