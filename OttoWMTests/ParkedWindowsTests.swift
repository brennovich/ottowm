import CoreGraphics
import XCTest

final class ParkedWindowsTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let parked = ParkedWindows()

    func testAWindowIsActiveUntilItIsParked() {
        XCTAssertEqual(parked.placement(of: 100), .active)
        XCTAssertNil(parked.owedFrame(of: 100))

        parked.park(100, owing: frame)

        XCTAssertEqual(parked.placement(of: 100), .parked)
        XCTAssertEqual(parked.owedFrame(of: 100), frame)
    }

    func testParkingAgainReplacesTheFrameTheWindowIsOwed() {
        let later = frame.offsetBy(dx: 50, dy: 50)
        parked.park(100, owing: frame)

        parked.park(100, owing: later)

        XCTAssertEqual(parked.owedFrame(of: 100), later)
    }

    func testForgettingLeavesTheWindowActive() {
        parked.park(100, owing: frame)

        parked.forget(100)

        XCTAssertEqual(parked.placement(of: 100), .active)
        XCTAssertNil(parked.owedFrame(of: 100))
    }

    func testRecordAppliesTheOutcomeOfEachPlacement() {
        let cases: [(name: String, parkedBefore: Bool, outcome: PlacementOutcome, owedFrame: CGRect?)] = [
            ("parks the window left at the hidden edge", false, .parked(100, owing: frame), frame),
            ("forgets the window left on screen", true, .activated(100), nil),
            ("keeps the frame owed by a window that is gone", true, .gone(100), frame),
        ]

        for testCase in cases {
            let parked = ParkedWindows()
            if testCase.parkedBefore {
                parked.park(100, owing: frame)
            }

            parked.record([testCase.outcome])

            XCTAssertEqual(parked.owedFrame(of: 100), testCase.owedFrame, testCase.name)
        }
    }

    func testAllListsEveryParkedWindowInIdOrder() {
        parked.park(300, owing: frame)
        parked.park(100, owing: frame.offsetBy(dx: 10, dy: 0))
        parked.park(200, owing: frame.offsetBy(dx: 20, dy: 0))
        parked.forget(200)

        XCTAssertEqual(parked.all.map(\.windowId), [100, 300])
        XCTAssertEqual(parked.all.map(\.owedFrame), [frame.offsetBy(dx: 10, dy: 0), frame])
    }
}
