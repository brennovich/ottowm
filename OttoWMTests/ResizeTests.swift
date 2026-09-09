import CoreGraphics
import XCTest

final class ResizeTests: XCTestCase {
    private let bounds = StubScreen.standard.visibleFrame
    private let frame = CGRect(x: 800, y: 500, width: 400, height: 300)

    func testChangesTheDimensionTheChangeNamesFromTheTopLeft() {
        let cases: [(name: String, change: Resize.Change, expected: CGRect)] = [
            ("wider", .wider, CGRect(x: 800, y: 500, width: 415, height: 300)),
            ("narrower", .narrower, CGRect(x: 800, y: 500, width: 385, height: 300)),
            ("taller", .taller, CGRect(x: 800, y: 500, width: 400, height: 315)),
            ("shorter", .shorter, CGRect(x: 800, y: 500, width: 400, height: 285)),
        ]

        for testCase in cases {
            let resize = Resize(change: testCase.change, points: 15)

            XCTAssertEqual(resize.frame(resizing: frame, within: bounds), testCase.expected, testCase.name)
        }
    }

    func testGrowthStopsAtTheEdgeOfTheBounds() {
        let cases: [(name: String, change: Resize.Change, frame: CGRect, expected: CGRect)] = [
            (
                "wider stops at the right",
                .wider,
                CGRect(x: 1382, y: 500, width: 400, height: 300),
                CGRect(x: 1382, y: 500, width: 410, height: 300)
            ),
            (
                "taller stops at the bottom",
                .taller,
                CGRect(x: 800, y: 810, width: 400, height: 300),
                CGRect(x: 800, y: 810, width: 400, height: 310)
            ),
        ]

        for testCase in cases {
            let resize = Resize(change: testCase.change, points: 100)

            XCTAssertEqual(resize.frame(resizing: testCase.frame, within: bounds), testCase.expected, testCase.name)
        }
    }

    func testWindowPastTheEdgeKeepsItsSize() {
        let cases: [(name: String, change: Resize.Change, frame: CGRect)] = [
            ("wider right of the right", .wider, CGRect(x: 1500, y: 500, width: 400, height: 300)),
            ("taller below the bottom", .taller, CGRect(x: 800, y: 1000, width: 400, height: 300)),
        ]

        for testCase in cases {
            let resize = Resize(change: testCase.change, points: 15)

            XCTAssertEqual(resize.frame(resizing: testCase.frame, within: bounds), testCase.frame, testCase.name)
        }
    }

    func testShrinkToZeroOrBelowKeepsTheFrame() {
        let cases: [(name: String, change: Resize.Change, frame: CGRect)] = [
            ("narrower to zero", .narrower, CGRect(x: 800, y: 500, width: 15, height: 300)),
            ("shorter below zero", .shorter, CGRect(x: 800, y: 500, width: 400, height: 10)),
        ]

        for testCase in cases {
            let resize = Resize(change: testCase.change, points: 15)

            XCTAssertEqual(resize.frame(resizing: testCase.frame, within: bounds), testCase.frame, testCase.name)
        }
    }
}
