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
}
