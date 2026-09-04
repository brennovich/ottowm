import CoreGraphics
import XCTest

final class WindowEnrollmentTests: EngineTestCase {
    func testAWindowNotYetOnScreenIsEnrolledByARetry() {
        offScreenWindowIds = [100]
        let win = add(StubWindow(id: 100))

        XCTAssertNil(enrollment.enroll(win.snapshot(), to: 1))
        XCTAssertEqual(workspaces.allWindowIds, [])

        offScreenWindowIds = []
        runScheduledRetries()

        XCTAssertEqual(workspaces.workspace(for: 100), workspaces.current)
        XCTAssertEqual(managed.placement(of: 100), .active)
    }

    func testTheRetriesStopWhenTheWindowStaysOffScreen() {
        offScreenWindowIds = [100]
        let win = add(StubWindow(id: 100))
        enrollment.enrollLater(win.snapshot())

        XCTAssertEqual(runScheduledRetries(), [0.1, 0.2, 0.4, 0.8])
        XCTAssertTrue(scheduledRetries.isEmpty)
        XCTAssertEqual(workspaces.allWindowIds, [])
    }

    func testNothingIsScheduledForAnInadmissibleWindow() {
        let win = add(StubWindow(id: 100, isFullScreen: true))

        XCTAssertNil(enrollment.enroll(win.snapshot(), to: 1))
        enrollment.enrollLater(win.snapshot())

        XCTAssertTrue(scheduledRetries.isEmpty)
    }
}
