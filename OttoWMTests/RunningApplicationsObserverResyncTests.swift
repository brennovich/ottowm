import XCTest

final class RunningApplicationsObserverResyncTests: XCTestCase {
    private let harness = RunningApplicationsObserverHarness()

    func testResyncTakesTheInventoryOfTheWatchedApplicationsAndStartsTheOnesThatAppeared() {
        harness.apps = [StubRunningApplication(pid: 901)]
        _ = harness.start()
        harness.apps.append(StubRunningApplication(pid: 902))
        harness.scans[901] = .active([100, 200])
        harness.scans[902] = .active([300])

        let windows = harness.observer.resync()

        XCTAssertEqual(Set(windows.map(\.id)), [100, 200, 300])
        XCTAssertEqual(harness.windowEvents.startedPids, [901, 902])
    }

    func testResyncSubscribesOnlyTheApplicationsTheFilterIncludes() {
        _ = harness.start()
        harness.apps = [StubRunningApplication(pid: 901), StubRunningApplication(pid: 902)]
        harness.excludedPids = [902]

        _ = harness.observer.resync()

        XCTAssertEqual(harness.windowEvents.startedPids, [901])
    }

    func testResyncRetriesAnApplicationThatDoesNotReply() {
        harness.apps = [StubRunningApplication(pid: 901)]
        _ = harness.start()
        harness.scans[901] = .unreachable

        _ = harness.observer.resync()

        XCTAssertFalse(harness.scheduledRetries.isEmpty)
    }

    // The sweep runs before the scan, so a window it drops is not handed back as one to
    // enroll again.
    func testResyncSweepsBeforeScanning() {
        harness.apps = [StubRunningApplication(pid: 901)]
        _ = harness.start()

        _ = harness.observer.resync()

        XCTAssertEqual(harness.windowEvents.calls, [.start(901), .sweep, .inventory(901)])
    }
}
