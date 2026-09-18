import AppKit

final class RunningApplicationsObserverHarness {
    let windowEvents = StubWindowEvents()
    let center = NotificationCenter()
    var apps: [NSRunningApplication] = []
    var excludedPids: Set<pid_t> = []
    // What one attempt against an application that is not answering costs, so a test
    // that runs the retries also spends the time they would really take.
    let retryStep: TimeInterval = 0.4
    var clock = Date(timeIntervalSinceReferenceDate: 0)

    private(set) var events: [WindowEvent] = []
    private(set) var scheduledRetries: [(delay: TimeInterval, work: () -> Void)] = []
    private(set) var retryDelays: [TimeInterval] = []
    private(set) var pendingLaunches: [() -> Void] = []

    lazy var observer = RunningApplicationsObserver(
        windowEvents: windowEvents,
        canSubscribe: { !self.excludedPids.contains($0.processIdentifier) },
        scheduleRetry: { delay, work in
            self.retryDelays.append(delay)
            self.scheduledRetries.append((delay, work))
        },
        whenFinishedLaunching: { _, finished in self.pendingLaunches.append(finished) },
        now: { self.clock },
        notificationCenter: center,
        runningApplications: { self.apps }
    )

    var scans: [pid_t: ScanAttempt] {
        get { windowEvents.scans }
        set { windowEvents.scans = newValue }
    }

    func start() -> [WindowSnapshot] {
        observer.start { self.events.append($0) }
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
