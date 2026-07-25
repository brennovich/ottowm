import XCTest

final class MainScreenTests: XCTestCase {
    func testTopLeftFrameFromCocoa() {
        let cases: [(name: String, cocoa: CGRect, primaryHeight: CGFloat, expected: CGRect)] = [
            (
                "primary full frame is a no-op",
                CGRect(x: 0, y: 0, width: 1440, height: 900),
                900,
                CGRect(x: 0, y: 0, width: 1440, height: 900)
            ),
            (
                "menu bar offset on the primary visible frame",
                CGRect(x: 0, y: 70, width: 1440, height: 805),
                900,
                CGRect(x: 0, y: 25, width: 1440, height: 805)
            ),
            (
                "non-zero origin above the primary flips to negative y",
                CGRect(x: 0, y: 900, width: 1440, height: 900),
                900,
                CGRect(x: 0, y: -900, width: 1440, height: 900)
            ),
            (
                "screen right of the primary keeps x and flips y",
                CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                900,
                CGRect(x: 1440, y: -180, width: 1920, height: 1080)
            ),
        ]

        for testCase in cases {
            let result = topLeftFrame(fromCocoa: testCase.cocoa, primaryHeight: testCase.primaryHeight)
            XCTAssertEqual(result, testCase.expected, testCase.name)
        }
    }
}
