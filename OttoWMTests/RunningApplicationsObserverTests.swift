import AppKit
import XCTest

final class RunningApplicationsObserverTests: XCTestCase {
    private let harness = RunningApplicationsObserverHarness()

    func testStartReturnsTheWindowsOfRunningAppsWithTheFocusedOneAmongThem() {
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.scans[901] = .active([100, 200], focused: 300)

        let snapshots = harness.start()

        XCTAssertEqual(snapshots.map(\.id), [100, 200, 300])
        XCTAssertEqual(harness.events, [])
    }

    // Subscribing means a handful of round trips into one process, and a process that does
    // not reply holds its thread for the whole messaging timeout. Serialised, one silent
    // process delays every application behind it.
    func testStartOverlapsTheApplicationsItSubscribes() {
        harness.apps = (1...8).map { StubRunningApplication(pid: pid_t(900 + $0)) }
        let firstStart = DispatchSemaphore(value: 1)
        let anotherStart = DispatchSemaphore(value: 0)
        harness.windowEvents.onStart = {
            if firstStart.wait(timeout: .now()) == .success {
                XCTAssertEqual(anotherStart.wait(timeout: .now() + 2), .success)
            } else {
                anotherStart.signal()
            }
        }

        _ = harness.start()

        XCTAssertEqual(harness.windowEvents.startedPids.count, 8)
    }

    func testStartSubscribesOnlyTheApplicationsTheFilterIncludes() {
        harness.apps = [StubRunningApplication(pid: 901), StubRunningApplication(pid: 902)]
        harness.scans[901] = .active([100])
        harness.scans[902] = .active([200])
        harness.excludedPids = [902]

        XCTAssertEqual(harness.start().map(\.id), [100])
        XCTAssertEqual(harness.windowEvents.startedPids, [901])
    }

    func testStartLeavesOutAnApplicationThatCannotBeWatched() {
        harness.apps = [StubRunningApplication(pid: 901), StubRunningApplication(pid: 902)]
        harness.scans[901] = .active([100])
        harness.scans[902] = .active([200])
        harness.windowEvents.failingNotificationPids = [901]

        XCTAssertEqual(harness.start().map(\.id), [200])
    }

    // An application listed at start is already running: gating it on finishedLaunching
    // would postpone the windows that are on screen right now.
    func testStartObservesAnApplicationThatHasNotFinishedLaunching() {
        harness.apps = [StubRunningApplication(pid: 901, hasFinishedLaunching: false)]
        harness.scans[901] = .active([100])

        XCTAssertEqual(harness.start().map(\.id), [100])
        XCTAssertTrue(harness.pendingLaunches.isEmpty)
    }

    func testWindowEventsReachTheHandler() {
        _ = harness.start()

        harness.windowEvents.report(.destroyed(100))

        XCTAssertEqual(harness.eventDescriptions, ["destroyed(100)"])
    }

    func testApplicationLaunchAnnouncesTheWindowsFoundAndThenTheFocusedOne() {
        _ = harness.start()
        harness.scans[901] = .active([100], focused: 300)

        harness.post(NSWorkspace.didLaunchApplicationNotification, StubRunningApplication(pid: 901))

        XCTAssertEqual(harness.eventDescriptions, ["created(100)", "focused(300)"])
    }

    func testApplicationLaunchWaitsForTheApplicationToFinishLaunching() {
        let app = StubRunningApplication(pid: 901, hasFinishedLaunching: false)
        _ = harness.start()
        harness.scans[901] = .active([100])

        harness.post(NSWorkspace.didLaunchApplicationNotification, app)

        XCTAssertEqual(harness.windowEvents.startedPids, [])

        app.hasFinishedLaunching = true
        harness.runPendingLaunches()

        XCTAssertEqual(harness.eventDescriptions, ["created(100)"])
    }

    func testApplicationLaunchThatDoesNotReplyIsRetriedUntilItReplies() {
        _ = harness.start()
        harness.scans[901] = .unreachable

        harness.post(NSWorkspace.didLaunchApplicationNotification, StubRunningApplication(pid: 901))

        XCTAssertEqual(harness.events, [])

        harness.scans[901] = .active([100])
        harness.runScheduledRetries()

        XCTAssertEqual(harness.eventDescriptions, ["created(100)"])
        XCTAssertTrue(harness.scheduledRetries.isEmpty)
    }

    // An application that subscribed and lists no window is not broken: its window, when
    // it opens one, arrives as a notification or on the scan its activation runs.
    func testApplicationThatSubscribesWithoutWindowsIsNotRetried() {
        _ = harness.start()

        harness.post(NSWorkspace.didLaunchApplicationNotification, StubRunningApplication(pid: 901))

        XCTAssertTrue(harness.scheduledRetries.isEmpty)
    }

    func testRetryWaitsTwiceAsLongAfterEachAttempt() {
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.scans[901] = .unreachable
        _ = harness.start()

        for _ in 1...4 { harness.runScheduledRetries() }

        XCTAssertEqual(harness.retryDelays, [0.1, 0.2, 0.4, 0.8, 1.6])
    }

    func testSubscriptionIsGivenUpOnceTheSubscriptionWindowHasPassed() {
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.scans[901] = .unreachable
        _ = harness.start()
        let started = harness.clock
        var attempts = 0

        while !harness.scheduledRetries.isEmpty {
            harness.runScheduledRetries()
            attempts += 1
        }

        let spent = harness.clock.timeIntervalSince(started)
        XCTAssertGreaterThanOrEqual(spent, RunningApplicationsObserver.subscriptionGracePeriod)
        XCTAssertLessThan(spent, RunningApplicationsObserver.subscriptionGracePeriod + harness.retryStep * 2)
        XCTAssertLessThanOrEqual(attempts, 10)
    }

    // `notificationUnsupported` means the process has no such notifications, not that it is
    // still waking up. Waiting out the grace period on it only spends the attempts again.
    func testSubscriptionIsNotRetriedForAProcessWithoutNotificationSupport() {
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.scans[901] = .unsupported

        _ = harness.start()

        XCTAssertTrue(harness.scheduledRetries.isEmpty)
    }

    func testApplicationLaunchSubscribesOnlyTheApplicationsTheFilterIncludes() {
        _ = harness.start()
        harness.excludedPids = [902]

        harness.post(NSWorkspace.didLaunchApplicationNotification, StubRunningApplication(pid: 901))
        harness.post(NSWorkspace.didLaunchApplicationNotification, StubRunningApplication(pid: 902))

        XCTAssertEqual(harness.windowEvents.startedPids, [901])
    }

    func testApplicationTerminationStopsWatchingTheApplication() {
        _ = harness.start()

        harness.post(NSWorkspace.didTerminateApplicationNotification, StubRunningApplication(pid: 901))

        XCTAssertEqual(harness.windowEvents.calls, [.stop(901)])
    }

    // A window closed by its button while its application is in the background takes no
    // activation with it, so every activation sweeps the windows of every application.
    func testApplicationActivationSweepsAndThenAnnouncesWhatTheApplicationOpened() {
        let app = StubRunningApplication(pid: 901)
        harness.apps = [app]
        _ = harness.start()
        harness.scans[901] = .active([300], focused: 200)

        harness.post(NSWorkspace.didActivateApplicationNotification, app)

        XCTAssertEqual(harness.windowEvents.calls.suffix(2), [.sweep, .discover(901)])
        XCTAssertEqual(harness.eventDescriptions, ["created(300)", "focused(200)"])
    }

    func testApplicationActivationScansOnlyTheApplicationsTheFilterIncludes() {
        let app = StubRunningApplication(pid: 901)
        harness.apps = [app]
        _ = harness.start()
        harness.excludedPids = [901]

        harness.post(NSWorkspace.didActivateApplicationNotification, app)

        XCTAssertEqual(harness.windowEvents.calls, [.start(901)])
    }

    func testRetryDoesNotSweep() {
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.scans[901] = .unreachable
        _ = harness.start()

        harness.runScheduledRetries()

        XCTAssertEqual(harness.windowEvents.calls, [.start(901), .discover(901)])
    }
}
