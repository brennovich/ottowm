import AppKit
import ApplicationServices
import CoreGraphics
import XCTest

private final class Harness {
    let windows = KnownWindowsHarness()
    let center = NotificationCenter()
    var apps: [NSRunningApplication] = []
    var focusedElements: [pid_t: AXUIElement] = [:]
    // What one attempt against an application that is not answering costs, so a test
    // that runs the retries also spends the time they would really take.
    let retryStep: TimeInterval = 0.4
    var clock = Date(timeIntervalSinceReferenceDate: 0)

    private(set) var events: [WindowEvent] = []
    private(set) var scheduledRetries: [() -> Void] = []

    lazy var observer = AXWindowObserver(
        knownWindows: windows.knownWindows,
        scheduleRetry: { self.scheduledRetries.append($0) },
        now: { self.clock },
        notificationCenter: center,
        runningApplications: { self.apps },
        focusedWindowOf: { app in
            self.focusedElements[app.processIdentifier].map {
                AXWindow(element: $0, application: app, id: self.windows.windowIds[$0] ?? 0)
            }
        }
    )

    var knownWindows: KnownWindows { windows.knownWindows }
    var callbacks: [pid_t: (AXUIElement, String) -> Void] { windows.callbacks }
    var invalidatedPids: [pid_t] { windows.invalidatedPids }
    var unreadyPids: Set<pid_t> {
        get { windows.unreadyPids }
        set { windows.unreadyPids = newValue }
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

    func runScheduledRetries() {
        let retries = scheduledRetries
        scheduledRetries = []
        clock.addTimeInterval(retryStep)
        retries.forEach { $0() }
    }

    func post(_ name: Notification.Name, _ app: NSRunningApplication) {
        center.post(name: name, object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: app])
    }

    var eventDescriptions: [String] {
        events.map {
            switch $0 {
            case let .created(win): "created(\(win.id))"
            case let .focused(win): "focused(\(win.id))"
            case let .destroyed(id): "destroyed(\(id))"
            case let .minimized(id): "minimized(\(id))"
            case let .unminimized(win): "unminimized(\(win.id))"
            }
        }
    }
}

final class AXWindowObserverTests: XCTestCase {

    func testStartReturnsTheWindowsOfRunningApps() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.addWindow(pid: 901, id: 100)
        harness.addWindow(pid: 901, id: 200)

        let snapshots = harness.start()

        XCTAssertEqual(snapshots.map(\.id), [100, 200])
        XCTAssertEqual(harness.events, [])
    }

    func testStartSkipsOwnPidAndNonRegularApps() {
        let harness = Harness()
        harness.apps = [
            StubRunningApplication(pid: ProcessInfo.processInfo.processIdentifier),
            StubRunningApplication(pid: 902, policy: .accessory),
            StubRunningApplication(pid: 903, policy: .prohibited),
        ]

        XCTAssertEqual(harness.start().count, 0)
        XCTAssertTrue(harness.callbacks.isEmpty)
    }

    func testStartSkipsAppWhenObserverCreationFails() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901), StubRunningApplication(pid: 902)]
        harness.addWindow(pid: 901, id: 100)
        harness.addWindow(pid: 902, id: 200)
        harness.windows.failingObserverPids = [901]

        XCTAssertEqual(harness.start().map(\.id), [200])
    }

    func testStartSkipsTheLockScreen() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901, bundleId: "com.apple.loginwindow")]
        harness.addWindow(pid: 901, id: 100)

        XCTAssertEqual(harness.start().count, 0)
        XCTAssertTrue(harness.callbacks.isEmpty)
    }

    func testWindowNotificationMapping() {
        let cases: [(notification: String, expected: [String])] = [
            (kAXWindowCreatedNotification, ["created(42)"]),
            (kAXFocusedWindowChangedNotification, ["focused(42)"]),
            (kAXWindowMiniaturizedNotification, ["minimized(42)"]),
            (kAXWindowDeminiaturizedNotification, ["unminimized(42)"]),
            ("AXSomethingElse", []),
        ]

        for testCase in cases {
            let harness = Harness()
            harness.apps = [StubRunningApplication(pid: 901)]
            _ = harness.start()
            let element = harness.makeElement(id: 42)

            harness.callbacks[901]?(element, testCase.notification)

            XCTAssertEqual(harness.eventDescriptions, testCase.expected, testCase.notification)
        }
    }

    func testNotificationsForWindowsWithoutIdAreDropped() {
        let notifications = [
            kAXWindowCreatedNotification,
            kAXFocusedWindowChangedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification,
        ]

        for notification in notifications {
            let harness = Harness()
            harness.apps = [StubRunningApplication(pid: 901)]
            _ = harness.start()
            let element = AXUIElementCreateApplication(5999)

            harness.callbacks[901]?(element, notification)

            XCTAssertEqual(harness.events, [], notification)
        }
    }

    func testDestroyedNotificationRemovesRegisteredWindow() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        let window = harness.addWindow(pid: 901, id: 100)
        _ = harness.start()

        harness.callbacks[901]?(window, kAXUIElementDestroyedNotification)

        XCTAssertEqual(harness.eventDescriptions, ["destroyed(100)"])
        XCTAssertFalse(harness.knownWindows.knows(window))
    }

    func testDestroyedNotificationForUnknownElementIsDropped() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        _ = harness.start()

        harness.callbacks[901]?(harness.makeElement(id: 42), kAXUIElementDestroyedNotification)

        XCTAssertEqual(harness.events, [])
    }

    func testApplicationLaunchObservesAndEmitsExistingWindows() {
        let harness = Harness()
        _ = harness.start()
        let app = StubRunningApplication(pid: 901)
        harness.addWindow(pid: 901, id: 100)

        harness.post(NSWorkspace.didLaunchApplicationNotification, app)

        XCTAssertEqual(harness.eventDescriptions, ["created(100)"])
        XCTAssertNotNil(harness.callbacks[901])
    }

    func testApplicationLaunchOfObservedAppDoesNothing() {
        let harness = Harness()
        let app = StubRunningApplication(pid: 901)
        harness.apps = [app]
        harness.addWindow(pid: 901, id: 100)
        _ = harness.start()

        harness.post(NSWorkspace.didLaunchApplicationNotification, app)

        XCTAssertEqual(harness.events, [])
    }

    func testApplicationLaunchWithUnreadyAccessibilityIsRetriedUntilItAnswers() {
        let harness = Harness()
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

    func testSuccessfulSubscriptionIsNotRetried() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.addWindow(pid: 901, id: 100)

        _ = harness.start()

        XCTAssertTrue(harness.scheduledRetries.isEmpty)
    }

    func testSubscriptionKeepsBeingRetriedForAnApplicationThatAnswersLate() {
        let harness = Harness()
        let app = StubRunningApplication(pid: 901)
        harness.unreadyPids = [901]
        _ = harness.start()
        harness.post(NSWorkspace.didLaunchApplicationNotification, app)

        // A cold Safari takes about seven attempts before its AX interface answers at all.
        for _ in 1...7 { harness.runScheduledRetries() }
        harness.unreadyPids = []
        harness.addWindow(pid: 901, id: 100)
        harness.runScheduledRetries()

        XCTAssertEqual(harness.eventDescriptions, ["created(100)"])
    }

    func testSubscriptionIsGivenUpOnceTheSubscriptionWindowHasPassed() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.unreadyPids = [901]
        _ = harness.start()
        let started = harness.clock

        while !harness.scheduledRetries.isEmpty {
            harness.runScheduledRetries()
        }

        let spent = harness.clock.timeIntervalSince(started)
        XCTAssertGreaterThanOrEqual(spent, AXWindowObserver.subscriptionGracePeriod)
        XCTAssertLessThan(spent, AXWindowObserver.subscriptionGracePeriod + harness.retryStep * 2)
    }

    func testRetryDoesNotReAnnounceKnownWindows() {
        let harness = Harness()
        let app = StubRunningApplication(pid: 901)
        harness.unreadyPids = [901]
        harness.addWindow(pid: 901, id: 100)
        _ = harness.start()
        harness.post(NSWorkspace.didLaunchApplicationNotification, app)

        XCTAssertEqual(harness.eventDescriptions, ["created(100)"])

        harness.unreadyPids = []
        harness.runScheduledRetries()

        XCTAssertEqual(harness.eventDescriptions, ["created(100)"])
    }

    func testApplicationLaunchIgnoresNonRegularApps() {
        let harness = Harness()
        _ = harness.start()

        harness.post(NSWorkspace.didLaunchApplicationNotification, StubRunningApplication(pid: 901, policy: .accessory))

        XCTAssertTrue(harness.callbacks.isEmpty)
    }

    func testApplicationTerminationStopsObservingTheApplication() {
        let harness = Harness()
        let app = StubRunningApplication(pid: 901)
        harness.apps = [app]
        _ = harness.start()

        harness.post(NSWorkspace.didTerminateApplicationNotification, app)

        XCTAssertEqual(harness.invalidatedPids, [901])
    }

    func testApplicationTerminationOfUnobservedAppDoesNothing() {
        let harness = Harness()
        _ = harness.start()

        harness.post(NSWorkspace.didTerminateApplicationNotification, StubRunningApplication(pid: 901))

        XCTAssertEqual(harness.invalidatedPids, [])
    }

    func testApplicationActivationRescansAndEmitsFocus() {
        let harness = Harness()
        let app = StubRunningApplication(pid: 901)
        harness.apps = [app]
        harness.addWindow(pid: 901, id: 100)
        _ = harness.start()
        let discovered = harness.addWindow(pid: 901, id: 200)
        harness.focusedElements[901] = discovered

        harness.post(NSWorkspace.didActivateApplicationNotification, app)

        XCTAssertEqual(harness.eventDescriptions, ["created(200)", "focused(200)"])
    }

    func testApplicationActivationWithoutFocusedWindowEmitsOnlyRescans() {
        let harness = Harness()
        let app = StubRunningApplication(pid: 901)
        harness.apps = [app]
        _ = harness.start()
        harness.addWindow(pid: 901, id: 200)

        harness.post(NSWorkspace.didActivateApplicationNotification, app)

        XCTAssertEqual(harness.eventDescriptions, ["created(200)"])
    }

    func testApplicationActivationOfUnobservedAppDoesNothing() {
        let harness = Harness()
        _ = harness.start()

        harness.post(NSWorkspace.didActivateApplicationNotification, StubRunningApplication(pid: 901))

        XCTAssertEqual(harness.events, [])
    }

    func testDropDeadWindowsAnnouncesTheOnesThatNoLongerAnswer() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.addWindow(pid: 901, id: 100)
        let dead = harness.addWindow(pid: 901, id: 200)
        _ = harness.start()
        harness.deadElements = [dead]

        harness.observer.dropDeadWindows()

        XCTAssertEqual(harness.eventDescriptions, ["destroyed(200)"])
    }

    // A window closed by its button while its application is in the background takes no
    // activation with it, so the sweep cannot be scoped to the application activated.
    func testApplicationActivationSweepsTheWindowsOfEveryApplication() {
        let harness = Harness()
        let activated = StubRunningApplication(pid: 901)
        harness.apps = [activated, StubRunningApplication(pid: 902)]
        harness.addWindow(pid: 901, id: 100)
        let dead = harness.addWindow(pid: 902, id: 200)
        _ = harness.start()
        harness.deadElements = [dead]

        harness.post(NSWorkspace.didActivateApplicationNotification, activated)

        XCTAssertEqual(harness.eventDescriptions, ["destroyed(200)"])
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
