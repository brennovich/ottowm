import CoreGraphics
import XCTest

final class WindowListTests: XCTestCase {
    func testOnScreenWindowIds() {
        let key = kCGWindowNumber as String
        let cases: [(name: String, infoList: [[String: Any]], expected: Set<CGWindowID>)] = [
            ("empty list", [], []),
            ("entries with window numbers", [[key: NSNumber(value: 100)], [key: NSNumber(value: 200)]], [100, 200]),
            ("entry missing the key", [[key: NSNumber(value: 100)], ["other": NSNumber(value: 200)]], [100]),
            ("non-number value", [[key: "not a number"], [key: NSNumber(value: 300)]], [300]),
            ("duplicate ids", [[key: NSNumber(value: 100)], [key: NSNumber(value: 100)]], [100]),
        ]

        for testCase in cases {
            XCTAssertEqual(onScreenWindowIds(from: testCase.infoList), testCase.expected, testCase.name)
        }
    }
}
