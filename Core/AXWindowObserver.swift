import AppKit

private let initialRetryDelay: TimeInterval = 0.1
private let lockScreenBundleId = "com.apple.loginwindow"

// WebKit runs one of these XPC services per tab, per network session and per GPU
// context, so a browser accounts for dozens of them. None owns a window and none
// answers the Accessibility API: every subscription attempt costs a full messaging
// timeout, and the retries spend it again until the grace period runs out.
private let webKitServiceBundleIds: Set<String> = [
    "com.apple.WebKit.WebContent",
    "com.apple.WebKit.Networking",
    "com.apple.WebKit.GPU",
]

final class AXWindowObserver {
    private let windowEvents: AXWindowEvents
    private let scheduleRetry: (TimeInterval, @escaping () -> Void) -> Void
    private let whenFinishedLaunching: (NSRunningApplication, @escaping () -> Void) -> Void
    private let now: () -> Date
    private let notificationCenter: NotificationCenter
    private let runningApplications: () -> [NSRunningApplication]
    private var handler: ((WindowEvent) -> Void)?
    private let ownPid = ProcessInfo.processInfo.processIdentifier

    static let subscriptionGracePeriod: TimeInterval = 15

    private static let workspaceNotifications: [(name: NSNotification.Name, selector: Selector)] = [
        (NSWorkspace.didLaunchApplicationNotification, #selector(applicationLaunched(_:))),
        (NSWorkspace.didTerminateApplicationNotification, #selector(applicationTerminated(_:))),
        (NSWorkspace.didActivateApplicationNotification, #selector(applicationActivated(_:))),
    ]

    init(
        windowEvents: AXWindowEvents,
        scheduleRetry: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        },
        whenFinishedLaunching: @escaping (NSRunningApplication, @escaping () -> Void) -> Void = { app, finished in
            var observation: NSKeyValueObservation?
            observation = app.observe(\.isFinishedLaunching) { app, _ in
                guard app.isFinishedLaunching else { return }

                observation?.invalidate()
                observation = nil
                finished()
            }
        },
        now: @escaping () -> Date = Date.init,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        runningApplications: @escaping () -> [NSRunningApplication] = { NSWorkspace.shared.runningApplications }
    ) {
        self.windowEvents = windowEvents
        self.scheduleRetry = scheduleRetry
        self.whenFinishedLaunching = whenFinishedLaunching
        self.now = now
        self.notificationCenter = notificationCenter
        self.runningApplications = runningApplications
    }

    func start(_ handler: @escaping (WindowEvent) -> Void) -> [WindowSnapshot] {
        self.handler = handler
        windowEvents.onEvent = { [weak self] in self?.handler?($0) }

        let windows = scan(runningApplications().filter(canSubscribe), windowEvents.start).flatMap(\.all)

        for n in Self.workspaceNotifications {
            notificationCenter.addObserver(self, selector: n.selector, name: n.name, object: nil)
        }

        return windows
    }

    /// Answers with every window of every running application, so the engine can adopt
    /// the ones no workspace knows. The sweep runs first: a window it drops must not come
    /// back in the answer as one to adopt again. An application that appeared while the
    /// screen was locked is not watched yet and is started like a launch, retries included.
    func resync() -> [WindowSnapshot] {
        windowEvents.sweepDeadWindows()

        return scan(runningApplications().filter(canSubscribe)) {
            windowEvents.inventory($0) ?? windowEvents.start($0)
        }.flatMap(\.all)
    }

    /// Each application is a group of its own: subscribing costs a handful of round trips
    /// into that process, and one that does not answer holds its thread for the messaging
    /// timeout instead of holding up every application behind it. One that answers
    /// unreachable is retried until the grace period runs out.
    private func scan(
        _ apps: [NSRunningApplication],
        _ attempt: (NSRunningApplication) -> AXWindowEvents.Attempt?
    ) -> [AXWindowEvents.Attempt] {
        let attempts = Concurrently.map(over: apps.map { [$0] }) {
            $0.compactMap { app in attempt(app).map { (app: app, attempt: $0) } }
        }

        let deadline = now().addingTimeInterval(Self.subscriptionGracePeriod)
        for started in attempts where started.attempt.subscription == .unreachable {
            retry(started.app, after: initialRetryDelay, until: deadline)
        }

        return attempts.map(\.attempt)
    }

    private func canSubscribe(_ app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        guard app.activationPolicy != .prohibited else {
            Log.observer.debug("skipping pid=\(pid) app=\(app.localizedName ?? ""): activation policy is prohibited")
            return false
        }
        guard pid != ownPid else { return false }
        guard let bundleId = app.bundleIdentifier else { return true }
        guard bundleId != lockScreenBundleId else {
            Log.observer.debug("skipping pid=\(pid) app=\(app.localizedName ?? ""): lock screen")
            return false
        }
        guard !webKitServiceBundleIds.contains(bundleId) else {
            Log.observer.debug("skipping pid=\(pid) app=\(app.localizedName ?? ""): WebKit service")
            return false
        }

        return true
    }

    // Exponential backoff retry, this is necessary because some apps take
    // a while to finish launching and become reachable via AX.
    private func retry(_ app: NSRunningApplication, after delay: TimeInterval, until deadline: Date) {
        guard now() < deadline else {
            let waited = Int(Self.subscriptionGracePeriod)
            let pid = app.processIdentifier
            let name = app.localizedName ?? ""
            Log.observer.error("giving up on pid=\(pid) app=\(name): unreachable for \(waited)s")
            return
        }

        scheduleRetry(min(delay, deadline.timeIntervalSince(now()))) { [weak self] in
            guard let self, let attempt = windowEvents.discover(app) else { return }

            announce(attempt)
            if attempt.subscription == .unreachable {
                retry(app, after: delay * 2, until: deadline)
            }
        }
    }

    private func app(from notification: Notification) -> NSRunningApplication? {
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    @objc private func applicationLaunched(_ notification: Notification) {
        guard let app = app(from: notification), canSubscribe(app) else { return }
        guard app.isFinishedLaunching else {
            whenFinishedLaunching(app) { [weak self] in self?.announceWindows(of: app) }
            return
        }

        announceWindows(of: app)
    }

    private func announceWindows(of app: NSRunningApplication) {
        scan([app], windowEvents.start).forEach(announce)
    }

    private func announce(_ attempt: AXWindowEvents.Attempt) {
        for window in attempt.windows {
            Log.observer.info("announcing \(window.logDescription)")
            handler?(.created(window))
        }
        if let focused = attempt.focused { handler?(.focused(focused)) }
    }

    @objc private func applicationTerminated(_ notification: Notification) {
        guard let app = app(from: notification) else { return }
        windowEvents.stop(app)
    }

    @objc private func applicationActivated(_ notification: Notification) {
        guard let app = app(from: notification), canSubscribe(app) else { return }

        windowEvents.sweepDeadWindows()
        if let attempt = windowEvents.discover(app) { announce(attempt) }
    }

    deinit {
        notificationCenter.removeObserver(self)
    }
}
