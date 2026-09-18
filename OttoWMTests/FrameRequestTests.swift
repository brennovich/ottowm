import CoreGraphics
import XCTest

final class FrameRequestTests: XCTestCase {
    func testKnownOutcomeKeepsTheFrameTheRequestCarries() {
        let original = CGRect(x: 100, y: 100, width: 800, height: 600)
        let cases: [(change: FrameChange, expected: FrameOutcome)] = [
            (.maximize(restoring: original), .filled(100, from: original)),
            (.park(from: original), .parked(100, from: original)),
            (.unpark(original), .parked(100, from: original)),
            (.park(from: nil), .active(100)),
            (.move(.east), .active(100)),
        ]

        for (change, expected) in cases {
            XCTAssertEqual(FrameRequest(windowId: 100, change: change).knownOutcome, expected, change.logDescription)
        }
    }
}
