import AppKit
import ApplicationServices
import CoreGraphics
import XCTest

private final class Harness {
    let windows = AXWindowEventsHarness()
    let center = NotificationCenter()
    var apps: [NSRunningApplication] = []
    // What one attempt against an application that is not answering costs, so a test
    // that runs the retries also spends the time they would really take.
    let retryStep: TimeInterval = 0.4
    var clock = Date(timeIntervalSinceReferenceDate: 0)

    private(set) var events: [WindowEvent] = []
    private(set) var scheduledRetries: [(delay: TimeInterval, work: () -> Void)] = []
    private(set) var retryDelays: [TimeInterval] = []
    private(set) var pendingLaunches: [() -> Void] = []

    lazy var observer = AXWindowObserver(
        windowEvents: windows.windowEvents,
        scheduleRetry: { delay, work in
            self.retryDelays.append(delay)
            self.scheduledRetries.append((delay, work))
        },
        whenFinishedLaunching: { _, finished in self.pendingLaunches.append(finished) },
        now: { self.clock },
        notificationCenter: center,
        runningApplications: { self.apps }
    )

    var callbacks: [pid_t: (AXUIElement, String) -> Void] { windows.callbacks }
    var focusedElements: [pid_t: AXUIElement] {
        get { windows.focusedElements }
        set { windows.focusedElements = newValue }
    }
    var invalidatedPids: [pid_t] { windows.invalidatedPids }
    var unreadyPids: Set<pid_t> {
        get { windows.unreadyPids }
        set { windows.unreadyPids = newValue }
    }
    var unsupportedPids: Set<pid_t> {
        get { windows.unsupportedPids }
        set { windows.unsupportedPids = newValue }
    }
    var deadElements: Set<AXUIElement> {
        get { windows.deadElements }
        set { windows.deadElements = newValue }
    }

    func start() -> [WindowSnapshot] {
        observer.start { self.events.append($0) }
    }

    func makeElement(id: CGWindowID) -> AXUIElement {
        windows.makeElement(id: id)
    }

    @discardableResult
    func addWindow(pid: pid_t, id: CGWindowID) -> AXUIElement {
        windows.addWindow(pid: pid, id: id)
    }

    func runPendingLaunches() {
        let pending = pendingLaunches
        pendingLaunches = []
        pending.forEach { $0() }
    }

    func runScheduledRetries() {
        let retries = scheduledRetries
        scheduledRetries = []
        for retry in retries {
            clock.addTimeInterval(retry.delay + retryStep)
            retry.work()
        }
    }

    func post(_ name: Notification.Name, _ app: NSRunningApplication) {
        center.post(name: name, object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: app])
    }

    var eventDescriptions: [String] { events.descriptions }
}

final class AXWindowObserverTests: XCTestCase {
    private let harness = Harness()

    func testStartReturnsTheWindowsOfRunningApps() {
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.addWindow(pid: 901, id: 100)
        harness.addWindow(pid: 901, id: 200)

        let snapshots = harness.start()

        XCTAssertEqual(snapshots.map(\.id), [100, 200])
        XCTAssertEqual(harness.events, [])
    }

    // Subscribing means a handful of round trips into one process, and a process that
    // does not answer holds its thread for the whole messaging timeout. Serialised, one
    // silent process delays every application behind it.
    func testStartOverlapsTheApplicationsItSubscribes() {
        harness.apps = (1...8).map { StubRunningApplication(pid: pid_t(900 + $0)) }
        let firstSubscribe = DispatchSemaphore(value: 1)
        let anotherSubscribe = DispatchSemaphore(value: 0)
        harness.windows.onSubscribe = {
            if firstSubscribe.wait(timeout: .now()) == .success {
                XCTAssertEqual(anotherSubscribe.wait(timeout: .now() + 2), .success)
            } else {
                anotherSubscribe.signal()
            }
        }

        _ = harness.start()

        XCTAssertEqual(harness.callbacks.count, 8)
    }

    func testStartSkipsOwnPidAndProhibitedApps() {
        harness.apps = [
            StubRunningApplication(pid: ProcessInfo.processInfo.processIdentifier),
            StubRunningApplication(pid: 903, policy: .prohibited),
        ]

        XCTAssertEqual(harness.start().count, 0)
        XCTAssertTrue(harness.callbacks.isEmpty)
    }

    func testStartReturnsTheWindowsOfAccessoryApps() {
        harness.apps = [StubRunningApplication(pid: 902, policy: .accessory)]
        harness.addWindow(pid: 902, id: 100)

        XCTAssertEqual(harness.start().map(\.id), [100])
    }

    func testStartSkipsAppWhenObserverCreationFails() {
        harness.apps = [StubRunningApplication(pid: 901), StubRunningApplication(pid: 902)]
        harness.addWindow(pid: 901, id: 100)
        harness.addWindow(pid: 902, id: 200)
        harness.windows.failingNotificationPids = [901]

        XCTAssertEqual(harness.start().map(\.id), [200])
    }

    func testStartSkipsTheLockScreen() {
        harness.apps = [StubRunningApplication(pid: 901, bundleId: "com.apple.loginwindow")]
        harness.addWindow(pid: 901, id: 100)

        XCTAssertEqual(harness.start().count, 0)
        XCTAssertTrue(harness.callbacks.isEmpty)
    }

    func testStartSkipsWebKitServiceProcesses() {
        harness.apps = [
            StubRunningApplication(pid: 901, bundleId: "com.apple.WebKit.WebContent"),
            StubRunningApplication(pid: 902, bundleId: "com.apple.WebKit.Networking"),
            StubRunningApplication(pid: 903, bundleId: "com.apple.WebKit.GPU"),
        ]
        harness.addWindow(pid: 901, id: 100)

        XCTAssertEqual(harness.start().count, 0)
        XCTAssertTrue(harness.callbacks.isEmpty)
    }

    // An application listed at start is already running: gating it on finishedLaunching
    // would postpone the windows that are on screen right now.
    func testStartObservesAnApplicationThatHasNotFinishedLaunching() {
        harness.apps = [StubRunningApplication(pid: 901, hasFinishedLaunching: false)]
        harness.addWindow(pid: 901, id: 100)

        XCTAssertEqual(harness.start().map(\.id), [100])
        XCTAssertTrue(harness.pendingLaunches.isEmpty)
    }

    // The translation itself is covered by AXWindowEventsTests; what matters here is
    // that the events a watched application reports reach the handler `start` installs.
    func testEventsOfAWatchedApplicationReachTheHandler() {
        harness.apps = [StubRunningApplication(pid: 901)]
        let window = harness.addWindow(pid: 901, id: 100)
        _ = harness.start()

        harness.callbacks[901]?(harness.makeElement(id: 42), kAXWindowCreatedNotification)
        harness.callbacks[901]?(window, kAXUIElementDestroyedNotification)

        XCTAssertEqual(harness.eventDescriptions, ["created(42)", "destroyed(100)"])
    }

    func testApplicationLaunchObservesAndEmitsExistingWindows() {
        _ = harness.start()
        let app = StubRunningApplication(pid: 901)
        harness.addWindow(pid: 901, id: 100)

        harness.post(NSWorkspace.didLaunchApplicationNotification, app)

        XCTAssertEqual(harness.eventDescriptions, ["created(100)"])
        XCTAssertNotNil(harness.callbacks[901])
    }

    func testApplicationLaunchOfObservedAppDoesNothing() {
        let app = StubRunningApplication(pid: 901)
        harness.apps = [app]
        harness.addWindow(pid: 901, id: 100)
        _ = harness.start()

        harness.post(NSWorkspace.didLaunchApplicationNotification, app)

        XCTAssertEqual(harness.events, [])
    }

    func testApplicationLaunchWaitsForTheApplicationToFinishLaunching() {
        let app = StubRunningApplication(pid: 901, hasFinishedLaunching: false)
        _ = harness.start()
        harness.addWindow(pid: 901, id: 100)

        harness.post(NSWorkspace.didLaunchApplicationNotification, app)

        XCTAssertEqual(harness.events, [])
        XCTAssertNil(harness.callbacks[901])
        XCTAssertTrue(harness.scheduledRetries.isEmpty)

        app.hasFinishedLaunching = true
        harness.runPendingLaunches()

        XCTAssertEqual(harness.eventDescriptions, ["created(100)"])
        XCTAssertNotNil(harness.callbacks[901])
    }

    func testApplicationLaunchWithUnreadyAccessibilityIsRetriedUntilItAnswers() {
        let app = StubRunningApplication(pid: 901)
        harness.unreadyPids = [901]
        _ = harness.start()

        harness.post(NSWorkspace.didLaunchApplicationNotification, app)

        XCTAssertEqual(harness.events, [])

        harness.unreadyPids = []
        harness.addWindow(pid: 901, id: 100)
        harness.runScheduledRetries()

        XCTAssertEqual(harness.eventDescriptions, ["created(100)"])
        XCTAssertTrue(harness.scheduledRetries.isEmpty)
    }

    // An application that subscribed and lists no window is not broken: its window, when
    // it opens one, arrives as a notification or on the scan its activation runs.
    func testApplicationThatSubscribesWithoutWindowsIsNotRetried() {
        let app = StubRunningApplication(pid: 901)
        _ = harness.start()

        harness.post(NSWorkspace.didLaunchApplicationNotification, app)

        XCTAssertEqual(harness.events, [])
        XCTAssertTrue(harness.scheduledRetries.isEmpty)
    }

    func testSubscriptionKeepsBeingRetriedForAnApplicationThatAnswersLate() {
        let app = StubRunningApplication(pid: 901)
        harness.unreadyPids = [901]
        _ = harness.start()
        harness.post(NSWorkspace.didLaunchApplicationNotification, app)

        // A cold Safari takes a few seconds before its AX interface answers at all.
        for _ in 1...5 { harness.runScheduledRetries() }
        harness.unreadyPids = []
        harness.addWindow(pid: 901, id: 100)
        harness.runScheduledRetries()

        XCTAssertEqual(harness.eventDescriptions, ["created(100)"])
    }

    func testRetryWaitsTwiceAsLongAfterEachAttempt() {
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.unreadyPids = [901]
        _ = harness.start()

        for _ in 1...4 { harness.runScheduledRetries() }

        XCTAssertEqual(harness.retryDelays, [0.1, 0.2, 0.4, 0.8, 1.6])
    }

    func testSubscriptionIsGivenUpOnceTheSubscriptionWindowHasPassed() {
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.unreadyPids = [901]
        _ = harness.start()
        let started = harness.clock
        var attempts = 0

        while !harness.scheduledRetries.isEmpty {
            harness.runScheduledRetries()
            attempts += 1
        }

        let spent = harness.clock.timeIntervalSince(started)
        XCTAssertGreaterThanOrEqual(spent, AXWindowObserver.subscriptionGracePeriod)
        XCTAssertLessThan(spent, AXWindowObserver.subscriptionGracePeriod + harness.retryStep * 2)
        XCTAssertLessThanOrEqual(attempts, 10)
    }

    func testRetryAnnouncesTheWindowsOnceTheApplicationSubscribes() {
        let app = StubRunningApplication(pid: 901)
        harness.unreadyPids = [901]
        harness.addWindow(pid: 901, id: 100)
        _ = harness.start()
        harness.post(NSWorkspace.didLaunchApplicationNotification, app)

        XCTAssertEqual(harness.events, [])

        harness.unreadyPids = []
        harness.runScheduledRetries()

        XCTAssertEqual(harness.eventDescriptions, ["created(100)"])

        harness.post(NSWorkspace.didActivateApplicationNotification, app)

        XCTAssertEqual(harness.eventDescriptions, ["created(100)"])
    }

    // `notificationUnsupported` is the process answering that it has no notifications
    // to give, not that it is still waking up. Waiting out the grace period on it only
    // spends the attempts again.
    func testSubscriptionIsNotRetriedForAProcessWithoutNotificationSupport() {
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.unsupportedPids = [901]

        _ = harness.start()

        XCTAssertTrue(harness.scheduledRetries.isEmpty)
    }

    func testApplicationLaunchIgnoresProhibitedApps() {
        _ = harness.start()

        harness.post(NSWorkspace.didLaunchApplicationNotification, StubRunningApplication(pid: 901, policy: .prohibited))

        XCTAssertTrue(harness.callbacks.isEmpty)
    }

    // Every new tab spawns a WebContent process, so the launch notification is the
    // path that would pay for them again and again.
    func testApplicationLaunchIgnoresWebKitServiceProcesses() {
        _ = harness.start()
        harness.addWindow(pid: 901, id: 100)

        harness.post(
            NSWorkspace.didLaunchApplicationNotification,
            StubRunningApplication(pid: 901, bundleId: "com.apple.WebKit.WebContent")
        )

        XCTAssertEqual(harness.events, [])
        XCTAssertTrue(harness.callbacks.isEmpty)
    }

    func testApplicationLaunchAnnouncesTheWindowsOfAccessoryApps() {
        _ = harness.start()
        harness.addWindow(pid: 901, id: 100)

        harness.post(NSWorkspace.didLaunchApplicationNotification, StubRunningApplication(pid: 901, policy: .accessory))

        XCTAssertEqual(harness.eventDescriptions, ["created(100)"])
    }

    func testApplicationTerminationStopsObservingTheApplication() {
        let app = StubRunningApplication(pid: 901)
        harness.apps = [app]
        _ = harness.start()

        harness.post(NSWorkspace.didTerminateApplicationNotification, app)

        XCTAssertEqual(harness.invalidatedPids, [901])
    }

    func testApplicationTerminationOfUnobservedAppDoesNothing() {
        _ = harness.start()

        harness.post(NSWorkspace.didTerminateApplicationNotification, StubRunningApplication(pid: 901))

        XCTAssertEqual(harness.invalidatedPids, [])
    }

    func testApplicationActivationScansAndEmitsFocus() {
        let app = StubRunningApplication(pid: 901)
        harness.apps = [app]
        harness.addWindow(pid: 901, id: 100)
        _ = harness.start()
        let focused = harness.addWindow(pid: 901, id: 200)
        harness.addWindow(pid: 901, id: 300)
        harness.focusedElements[901] = focused

        harness.post(NSWorkspace.didActivateApplicationNotification, app)

        XCTAssertEqual(harness.eventDescriptions, ["created(300)", "focused(200)"])
    }

    func testApplicationActivationOfUnobservedAppDoesNothing() {
        _ = harness.start()

        harness.post(NSWorkspace.didActivateApplicationNotification, StubRunningApplication(pid: 901))

        XCTAssertEqual(harness.events, [])
    }

    // A window closed by its button while its application is in the background takes no
    // activation with it, so the sweep cannot be scoped to the application activated.
    func testApplicationActivationSweepsTheWindowsOfEveryApplication() {
        let activated = StubRunningApplication(pid: 901)
        harness.apps = [activated, StubRunningApplication(pid: 902)]
        harness.addWindow(pid: 901, id: 100)
        let dead = harness.addWindow(pid: 902, id: 200)
        _ = harness.start()
        harness.deadElements = [dead]

        harness.post(NSWorkspace.didActivateApplicationNotification, activated)
        harness.post(NSWorkspace.didActivateApplicationNotification, activated)

        XCTAssertEqual(harness.eventDescriptions, ["destroyed(200)"])
    }

    func testRetryDoesNotSweepTheWindowsOfOtherApplications() {
        harness.apps = [StubRunningApplication(pid: 901), StubRunningApplication(pid: 902)]
        harness.unreadyPids = [901]
        let dead = harness.addWindow(pid: 902, id: 200)
        _ = harness.start()
        harness.deadElements = [dead]

        harness.runScheduledRetries()
        harness.runScheduledRetries()

        XCTAssertEqual(harness.events, [])
        XCTAssertFalse(harness.scheduledRetries.isEmpty)
    }

    func testResyncAnswersWithTheWindowsOfEveryRunningApplication() {
        harness.apps = [StubRunningApplication(pid: 901), StubRunningApplication(pid: 902)]
        harness.addWindow(pid: 901, id: 100)
        _ = harness.start()
        harness.addWindow(pid: 901, id: 200)
        harness.addWindow(pid: 902, id: 300)

        let windows = harness.observer.resync()

        XCTAssertEqual(Set(windows.map(\.id)), [100, 200, 300])
    }

    func testResyncSubscribesAnApplicationThatAppearedWhileTheScreenWasLocked() {
        _ = harness.start()
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.addWindow(pid: 901, id: 100)

        let windows = harness.observer.resync()

        XCTAssertEqual(windows.map(\.id), [100])
        XCTAssertNotNil(harness.callbacks[901])
    }

    // The sweep runs before the scan, so a window it drops is not handed back as one to
    // adopt again.
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

extension WindowEvent: Equatable {
    public static func == (lhs: WindowEvent, rhs: WindowEvent) -> Bool {
        switch (lhs, rhs) {
        case let (.created(a), .created(b)): a == b
        case let (.focused(a), .focused(b)): a == b
        case let (.destroyed(a), .destroyed(b)): a == b
        case let (.minimized(a), .minimized(b)): a == b
        case let (.unminimized(a), .unminimized(b)): a == b
        default: false
        }
    }
}
