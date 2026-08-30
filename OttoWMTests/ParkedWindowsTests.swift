import CoreGraphics
import XCTest

final class ParkedWindowsTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let parked = ParkedWindows()

    func testAWindowIsActiveUntilItIsParked() {
        XCTAssertEqual(parked.placement(of: 100), .active)
        XCTAssertNil(parked.owedFrame(of: 100))

        parked.park(100, owing: frame)

        XCTAssertEqual(parked.placement(of: 100), .storage)
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

    func testRecordParksTheWindowsLeftAtTheHiddenEdge() {
        parked.record([.parked(100, owing: frame)])

        XCTAssertEqual(parked.owedFrame(of: 100), frame)
    }

    func testRecordForgetsTheWindowsLeftOnScreen() {
        parked.park(100, owing: frame)

        parked.record([.onScreen(100)])

        XCTAssertEqual(parked.placement(of: 100), .active)
    }

    func testRecordKeepsTheFrameOwedByAWindowThatIsGone() {
        parked.park(100, owing: frame)

        parked.record([.gone(100)])

        XCTAssertEqual(parked.owedFrame(of: 100), frame)
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
