import AppKit
import ApplicationServices
import CoreGraphics

final class RunningApplicationsObserverHarness {
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

    lazy var observer = RunningApplicationsObserver(
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
