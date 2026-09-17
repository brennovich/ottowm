import CoreGraphics
import XCTest

final class ParkedWindowsTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let parked = ParkedWindows()

    func testAWindowIsActiveUntilItIsParked() {
        XCTAssertFalse(parked.isParked(100))
        XCTAssertNil(parked.parkedFrom(of: 100))

        parked.park(100, from: frame)

        XCTAssertTrue(parked.isParked(100))
        XCTAssertEqual(parked.parkedFrom(of: 100), frame)
    }

    func testParkingAgainReplacesTheFrameTheWindowWasParkedFrom() {
        let later = frame.offsetBy(dx: 50, dy: 50)
        parked.park(100, from: frame)

        parked.park(100, from: later)

        XCTAssertEqual(parked.parkedFrom(of: 100), later)
    }

    func testForgettingLeavesTheWindowActive() {
        parked.park(100, from: frame)

        parked.forget(100)

        XCTAssertFalse(parked.isParked(100))
        XCTAssertNil(parked.parkedFrom(of: 100))
    }

    func testRecordAppliesTheOutcomeOfEachChange() {
        let cases: [(name: String, parkedBefore: Bool, outcome: FrameOutcome, parkedFrom: CGRect?)] = [
            ("parks the window left at the hidden edge", false, .parked(100, from: frame), frame),
            ("forgets the window left on screen", true, .active(100), nil),
            ("keeps the frame of a window that is gone", true, .gone(100), frame),
        ]

        for testCase in cases {
            let parked = ParkedWindows()
            if testCase.parkedBefore {
                parked.park(100, from: frame)
            }

            parked.record([testCase.outcome])

            XCTAssertEqual(parked.parkedFrom(of: 100), testCase.parkedFrom, testCase.name)
        }
    }
}
