import AppKit
import ApplicationServices
import CoreGraphics
import XCTest

private final class Harness {
    let registry = WindowRegistry()
    let center = NotificationCenter()
    var apps: [NSRunningApplication] = []
    var elements: [pid_t: [AXUIElement]] = [:]
    var windowIds: [AXUIElement: CGWindowID] = [:]
    var focusedElements: [pid_t: AXUIElement] = [:]
    var systemFocusedWindow: AXWindow?
    var failingObserverPids: Set<pid_t> = []
    var unreadyPids: Set<pid_t> = []
    var deadElements: Set<AXUIElement> = []

    private(set) var watched: [pid_t: [(element: AXUIElement, notification: String)]] = [:]
    private(set) var callbacks: [pid_t: (AXUIElement, String) -> Void] = [:]
    private(set) var invalidatedPids: [pid_t] = []
    private(set) var events: [WindowEvent] = []
    private(set) var scheduledRetries: [() -> Void] = []

    private var nextElementToken: pid_t = 5000

    lazy var observer = AXWindowObserver(
        registry: registry,
        focusedWindow: { self.systemFocusedWindow },
        makeObserver: { pid, callback in
            guard !self.failingObserverPids.contains(pid) else { return nil }
            self.callbacks[pid] = callback
            return AppObserver(
                watch: {
                    self.watched[pid, default: []].append(($0, $1))
                    return !self.unreadyPids.contains(pid)
                },
                invalidate: { self.invalidatedPids.append(pid) }
            )
        },
        scheduleRetry: { self.scheduledRetries.append($0) },
        notificationCenter: center,
        runningApplications: { self.apps },
        windowElements: { self.elements[$0] ?? [] },
        makeWindow: { AXWindow(element: $0, application: $1, id: self.windowIds[$0] ?? 0) },
        focusedWindowOf: { app in
            self.focusedElements[app.processIdentifier].map {
                AXWindow(element: $0, application: app, id: self.windowIds[$0] ?? 0)
            }
        },
        isAlive: { !self.deadElements.contains($0) }
    )

    func start() -> [WindowSnapshot] {
        observer.start { self.events.append($0) }
    }

    func makeElement(id: CGWindowID) -> AXUIElement {
        let element = AXUIElementCreateApplication(nextElementToken)
        nextElementToken += 1
        windowIds[element] = id
        return element
    }

    @discardableResult
    func addWindow(pid: pid_t, id: CGWindowID) -> AXUIElement {
        let element = makeElement(id: id)
        elements[pid, default: []].append(element)
        return element
    }

    func runScheduledRetries() {
        let retries = scheduledRetries
        scheduledRetries = []
        retries.forEach { $0() }
    }

    func appNotificationCount(pid: pid_t) -> Int {
        watched[pid]?.filter { $0.notification == kAXWindowCreatedNotification }.count ?? 0
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

private let windowNotifications = [
    kAXUIElementDestroyedNotification,
    kAXWindowMiniaturizedNotification,
    kAXWindowDeminiaturizedNotification,
]

final class AXWindowObserverTests: XCTestCase {

    func testStartReturnsAndRegistersWindowsOfRunningApps() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        let first = harness.addWindow(pid: 901, id: 100)
        let second = harness.addWindow(pid: 901, id: 200)

        let snapshots = harness.start()

        XCTAssertEqual(snapshots.map(\.id), [100, 200])
        XCTAssertTrue(harness.registry.knows(first))
        XCTAssertTrue(harness.registry.knows(second))
        XCTAssertEqual(harness.events, [])
    }

    func testStartWatchesAppAndWindowNotifications() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        let window = harness.addWindow(pid: 901, id: 100)

        _ = harness.start()

        XCTAssertEqual(harness.watched[901]?.map(\.notification), [
            kAXWindowCreatedNotification,
            kAXFocusedWindowChangedNotification,
        ] + windowNotifications)
        XCTAssertEqual(harness.watched[901]?.first?.element, AXUIElementCreateApplication(901))
        XCTAssertEqual(harness.watched[901]?.last?.element, window)
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
        harness.failingObserverPids = [901]

        let snapshots = harness.start()

        XCTAssertEqual(snapshots.map(\.id), [200])
        XCTAssertNil(harness.registry.application(for: 901))
        XCTAssertNotNil(harness.registry.application(for: 902))
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

    func testCreatedWindowIsRegisteredAndWatched() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        _ = harness.start()
        let element = harness.makeElement(id: 42)

        harness.callbacks[901]?(element, kAXWindowCreatedNotification)

        XCTAssertTrue(harness.registry.knows(element))
        XCTAssertEqual(harness.watched[901]?.suffix(3).map(\.notification), windowNotifications)
    }

    func testDestroyedNotificationRemovesRegisteredWindow() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        let window = harness.addWindow(pid: 901, id: 100)
        _ = harness.start()

        harness.callbacks[901]?(window, kAXUIElementDestroyedNotification)

        XCTAssertEqual(harness.eventDescriptions, ["destroyed(100)"])
        XCTAssertFalse(harness.registry.knows(window))
    }

    func testDestroyedNotificationForUnknownElementIsDropped() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        _ = harness.start()

        harness.callbacks[901]?(harness.makeElement(id: 42), kAXUIElementDestroyedNotification)

        XCTAssertEqual(harness.events, [])
    }

    func testFocusedUnknownWindowIsAdopted() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        _ = harness.start()
        let element = harness.makeElement(id: 42)

        harness.callbacks[901]?(element, kAXFocusedWindowChangedNotification)

        XCTAssertEqual(harness.eventDescriptions, ["focused(42)"])
        XCTAssertTrue(harness.registry.knows(element))
        XCTAssertEqual(harness.watched[901]?.suffix(3).map(\.notification), windowNotifications)
    }

    func testFocusedKnownWindowIsNotReAdopted() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        let window = harness.addWindow(pid: 901, id: 100)
        _ = harness.start()
        let watchCount = harness.watched[901]?.count

        harness.callbacks[901]?(window, kAXFocusedWindowChangedNotification)

        XCTAssertEqual(harness.eventDescriptions, ["focused(100)"])
        XCTAssertEqual(harness.watched[901]?.count, watchCount)
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
        let window = harness.addWindow(pid: 901, id: 100)
        harness.runScheduledRetries()

        XCTAssertEqual(harness.eventDescriptions, ["created(100)"])
        XCTAssertTrue(harness.registry.knows(window))
        XCTAssertEqual(harness.appNotificationCount(pid: 901), 2)
        XCTAssertTrue(harness.scheduledRetries.isEmpty)
    }

    func testSuccessfulSubscriptionIsNotRetried() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.addWindow(pid: 901, id: 100)

        _ = harness.start()

        XCTAssertTrue(harness.scheduledRetries.isEmpty)
    }

    func testSubscriptionIsGivenUpAfterTheAttemptLimit() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.unreadyPids = [901]
        _ = harness.start()

        while !harness.scheduledRetries.isEmpty {
            harness.runScheduledRetries()
        }

        XCTAssertEqual(harness.appNotificationCount(pid: 901), AXWindowObserver.subscriptionAttempts)
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

    func testApplicationTerminationInvalidatesAndEvicts() {
        let harness = Harness()
        let app = StubRunningApplication(pid: 901)
        harness.apps = [app]
        let window = harness.addWindow(pid: 901, id: 100)
        _ = harness.start()

        harness.post(NSWorkspace.didTerminateApplicationNotification, app)

        XCTAssertEqual(harness.invalidatedPids, [901])
        XCTAssertNil(harness.registry.application(for: 901))
        XCTAssertFalse(harness.registry.knows(window))
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
        XCTAssertTrue(harness.registry.knows(discovered))
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

    func testDropDeadWindowsAnnouncesAndForgetsTheOnesThatNoLongerAnswer() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        let alive = harness.addWindow(pid: 901, id: 100)
        let dead = harness.addWindow(pid: 901, id: 200)
        _ = harness.start()
        harness.deadElements = [dead]

        harness.observer.dropDeadWindows()

        XCTAssertEqual(harness.eventDescriptions, ["destroyed(200)"])
        XCTAssertFalse(harness.registry.knows(dead))
        XCTAssertTrue(harness.registry.knows(alive))
    }

    func testDropDeadWindowsKeepsEveryWindowThatStillAnswers() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        harness.addWindow(pid: 901, id: 100)
        _ = harness.start()

        harness.observer.dropDeadWindows()

        XCTAssertEqual(harness.events, [])
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
        XCTAssertFalse(harness.registry.knows(dead))
    }

    func testAdoptFocusedWindowAdoptsAndReturnsTheFocusedWindow() {
        let harness = Harness()
        let app = StubRunningApplication(pid: 901)
        harness.apps = [app]
        _ = harness.start()
        let element = harness.makeElement(id: 42)
        harness.systemFocusedWindow = AXWindow(element: element, application: app, id: 42)

        let window = harness.observer.adoptFocusedWindow()

        XCTAssertTrue(window === harness.systemFocusedWindow)
        XCTAssertTrue(harness.registry.knows(element))
        XCTAssertEqual(harness.watched[901]?.suffix(3).map(\.notification), windowNotifications)
    }

    func testAdoptFocusedWindowWithoutFocusReturnsNil() {
        let harness = Harness()
        harness.apps = [StubRunningApplication(pid: 901)]
        _ = harness.start()

        XCTAssertNil(harness.observer.adoptFocusedWindow())
    }

    func testAdoptFocusedKnownWindowReturnsItWithoutRewatching() {
        let harness = Harness()
        let app = StubRunningApplication(pid: 901)
        harness.apps = [app]
        let element = harness.addWindow(pid: 901, id: 100)
        _ = harness.start()
        let watchCount = harness.watched[901]?.count
        harness.systemFocusedWindow = AXWindow(element: element, application: app, id: 100)

        let window = harness.observer.adoptFocusedWindow()

        XCTAssertTrue(window === harness.systemFocusedWindow)
        XCTAssertEqual(harness.watched[901]?.count, watchCount)
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
