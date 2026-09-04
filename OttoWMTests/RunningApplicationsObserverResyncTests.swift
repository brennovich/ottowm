import XCTest

final class RunningApplicationsObserverResyncTests: XCTestCase {
    private let harness = RunningApplicationsObserverHarness()

    func testResyncAnswersWithTheWindowsOfEveryRunningApplicationSubscribingTheOnesThatAppeared() {
        harness.apps = [StubRunningApplication(pid: 901), StubRunningApplication(pid: 902)]
        harness.addWindow(pid: 901, id: 100)
        _ = harness.start()
        harness.addWindow(pid: 901, id: 200)
        harness.addWindow(pid: 902, id: 300)
        harness.apps.append(StubRunningApplication(pid: 903))
        harness.addWindow(pid: 903, id: 400)

        let windows = harness.observer.resync()

        XCTAssertEqual(Set(windows.map(\.id)), [100, 200, 300, 400])
        XCTAssertNotNil(harness.callbacks[903])
    }

    func testResyncRetriesAnApplicationThatAppearedWhileTheScreenWasLockedAndDoesNotAnswer() {
        _ = harness.start()
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.unreadyPids = [901]

        XCTAssertEqual(harness.observer.resync().map(\.id), [])
        XCTAssertFalse(harness.scheduledRetries.isEmpty)
    }

    func testResyncRetriesAKnownApplicationThatStillDoesNotAnswer() {
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.unreadyPids = [901]
        _ = harness.start()
        while !harness.scheduledRetries.isEmpty { harness.runScheduledRetries() }

        _ = harness.observer.resync()

        XCTAssertFalse(harness.scheduledRetries.isEmpty)
    }

    // The sweep runs before the scan, so a window it drops is not handed back as one to
    // enroll again.
    func testResyncSweepsTheWindowsThatNoLongerAnswerBeforeScanning() {
        harness.apps = [StubRunningApplication(pid: 901)]
        let dead = harness.addWindow(pid: 901, id: 100)
        let alive = harness.addWindow(pid: 901, id: 200)
        _ = harness.start()
        harness.deadElements = [dead]
        harness.windows.elements[901] = [alive]
        _ = harness.observer.resync()

        let windows = harness.observer.resync()

        XCTAssertEqual(harness.eventDescriptions, ["destroyed(100)"])
        XCTAssertEqual(windows.map(\.id), [200])
    }
}
