import CoreGraphics
import XCTest

final class FitTests: XCTestCase {
    private let large = CGRect(x: 0, y: 0, width: 2000, height: 1000)
    private let small = CGRect(x: 0, y: 25, width: 1000, height: 500)

    func testFrame() {
        let cases: [(name: String, fit: Fit, frame: CGRect, expected: CGRect)] = [
            (
                "keeps the share of the room on each axis",
                Fit(from: large, into: small),
                CGRect(x: 400, y: 350, width: 400, height: 300),
                CGRect(x: 150, y: 125, width: 400, height: 300)
            ),
            (
                "a window at the bottom right stays there",
                Fit(from: large, into: small),
                CGRect(x: 1600, y: 700, width: 400, height: 300),
                CGRect(x: 600, y: 225, width: 400, height: 300)
            ),
            (
                "a window wider than the frame entered takes its width",
                Fit(from: large, into: small),
                CGRect(x: 100, y: 350, width: 2400, height: 300),
                CGRect(x: 0, y: 125, width: 1000, height: 300)
            ),
            (
                "a window larger than the frame entered takes it whole",
                Fit(from: large, into: small),
                CGRect(x: 100, y: 100, width: 3000, height: 2000),
                CGRect(x: 0, y: 25, width: 1000, height: 500)
            ),
            (
                "a window hanging off an edge comes inside",
                Fit(from: large, into: small),
                CGRect(x: -200, y: 0, width: 400, height: 300),
                CGRect(x: 0, y: 25, width: 400, height: 300)
            ),
            (
                "the way back returns the frame",
                Fit(from: small, into: large),
                CGRect(x: 150, y: 125, width: 400, height: 300),
                CGRect(x: 400, y: 350, width: 400, height: 300)
            ),
        ]

        for testCase in cases {
            XCTAssertEqual(testCase.fit.frame(testCase.frame), testCase.expected, testCase.name)
        }
    }
}
