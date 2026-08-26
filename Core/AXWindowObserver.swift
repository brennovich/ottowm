import AppKit
import ApplicationServices
import CoreGraphics

private let subscriptionRetryDelay: TimeInterval = 0.1
private let lockScreenBundleId = "com.apple.loginwindow"

/// Turns per-application `AXObserver`s and `NSWorkspace` notifications into `WindowEvent`s:
/// created, focused, destroyed, minimized and unminimized. `KnownWindows` holds the
/// windows and their subscriptions; every event OttoWM sees is emitted here.
final class AXWindowObserver {
    private typealias Observed = (windows: [WindowSnapshot], subscribed: Bool)

    private let knownWindows: KnownWindows
    private let scheduleRetry: (@escaping () -> Void) -> Void
    private let now: () -> Date
    private let notificationCenter: NotificationCenter
    private let runningApplications: () -> [NSRunningApplication]
    private let focusedWindowOf: (NSRunningApplication) -> AXWindow?
    private var handler: ((WindowEvent) -> Void)?
    private let ownPid = ProcessInfo.processInfo.processIdentifier

    /// A freshly launched application can take seconds to answer AX, and announces no
    /// window until it does, hence the retries. An application that fails every retry is
    /// given up on; it may have no AX interface.
    static let subscriptionGracePeriod: TimeInterval = 15

    private static let workspaceNotifications: [(name: NSNotification.Name, selector: Selector)] = [
        (NSWorkspace.didLaunchApplicationNotification, #selector(applicationLaunched(_:))),
        (NSWorkspace.didTerminateApplicationNotification, #selector(applicationTerminated(_:))),
        (NSWorkspace.didActivateApplicationNotification, #selector(applicationActivated(_:))),
    ]

    init(
        knownWindows: KnownWindows,
        scheduleRetry: @escaping (@escaping () -> Void) -> Void = { work in
            DispatchQueue.main.asyncAfter(deadline: .now() + subscriptionRetryDelay, execute: work)
        },
        now: @escaping () -> Date = Date.init,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        runningApplications: @escaping () -> [NSRunningApplication] = { NSWorkspace.shared.runningApplications },
        focusedWindowOf: @escaping (NSRunningApplication) -> AXWindow? = AXWindow.focused(of:)
    ) {
        self.knownWindows = knownWindows
        self.scheduleRetry = scheduleRetry
        self.now = now
        self.notificationCenter = notificationCenter
        self.runningApplications = runningApplications
        self.focusedWindowOf = focusedWindowOf
    }

    /// Announces the windows that died without a notification. Called when an application
    /// comes to front and when the screen unlocks, the two moments a stale entry starts to
    /// matter.
    func dropDeadWindows() {
        for id in knownWindows.dropDead() {
            handler?(.destroyed(id))
        }
    }

    /// Subscribes to every observable application and to launch and terminate notifications.
    /// - Returns: the windows found while registering the observers, so the caller can
    ///   seed the model without sweeping every application again.
    func start(_ handler: @escaping (WindowEvent) -> Void) -> [WindowSnapshot] {
        self.handler = handler

        let windows = runningApplications()
            .filter(canObserve)
            .flatMap { observe($0) }

        for n in Self.workspaceNotifications {
            notificationCenter.addObserver(self, selector: n.selector, name: n.name, object: nil)
        }

        return windows
    }

    private func event(for element: AXUIElement, notification: String, app: NSRunningApplication) -> WindowEvent? {
        switch notification {
        case kAXWindowCreatedNotification:
            return knownWindows.watch(element, of: app).map { .created($0.snapshot()) }
        case kAXFocusedWindowChangedNotification:
            return knownWindows.adopt(element, of: app).map { .focused($0.snapshot()) }
        case kAXUIElementDestroyedNotification:
            return knownWindows.removeWindow(for: element).map(WindowEvent.destroyed)
        case kAXWindowMiniaturizedNotification:
            return knownWindows.window(of: element, in: app).map { .minimized($0.id) }
        case kAXWindowDeminiaturizedNotification:
            return knownWindows.window(of: element, in: app).map { .unminimized($0.snapshot()) }
        default:
            return nil
        }
    }

    /// The login window must not be managed.
    private func canObserve(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.processIdentifier != ownPid
            && app.bundleIdentifier != lockScreenBundleId
    }

    private func observe(_ app: NSRunningApplication) -> [WindowSnapshot] {
        guard let observed = knownWindows.observe(app, notify: { [weak self] element, notification in
            guard let self else { return }
            guard let event = event(for: element, notification: notification, app: app) else {
                Log.observer.debug("dropped \(notification)")
                return
            }
            handler?(event)
        }) else { return [] }

        retry(app, observed, until: now().addingTimeInterval(Self.subscriptionGracePeriod))

        return observed.windows
    }

    /// Asks the application again until its subscriptions are in place and it lists a
    /// window.
    ///
    /// A just launched application can report the subscriptions in place and list no
    /// window, and then open one without sending kAXWindowCreated. Nothing else would
    /// find that window until the user focuses the application again.
    private func retry(_ app: NSRunningApplication, _ observed: Observed, until deadline: Date) {
        guard !observed.subscribed || !knownWindows.hasWindows(of: app) else { return }

        guard now() < deadline else {
            let waited = Int(Self.subscriptionGracePeriod)
            let pid = app.processIdentifier
            let name = app.localizedName ?? ""
            if observed.subscribed {
                Log.observer.info("pid=\(pid) app=\(name) listed no window in \(waited)s, waiting for its notifications")
            } else {
                Log.observer.error("giving up on pid=\(pid) app=\(name): unreachable for \(waited)s")
            }
            return
        }

        scheduleRetry { [weak self] in
            guard let self, let observed = knownWindows.resubscribe(to: app) else { return }

            for snapshot in observed.windows {
                Log.observer.info("retry found window \(snapshot.logDescription)")
                handler?(.created(snapshot))
            }

            retry(app, observed, until: deadline)
        }
    }

    private func app(from notification: Notification) -> NSRunningApplication? {
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    @objc private func applicationLaunched(_ notification: Notification) {
        guard let app = app(from: notification), canObserve(app) else { return }
        for snapshot in observe(app) {
            handler?(.created(snapshot))
        }
    }

    @objc private func applicationTerminated(_ notification: Notification) {
        guard let app = app(from: notification) else { return }
        knownWindows.stopObserving(app)
    }

    @objc private func applicationActivated(_ notification: Notification) {
        guard let app = app(from: notification), canObserve(app), knownWindows.isObserving(app)
        else { return }

        dropDeadWindows()

        for snapshot in knownWindows.rescan(app) {
            Log.observer.info("rescan found window \(snapshot.logDescription)")
            handler?(.created(snapshot))
        }
        guard let window = focusedWindowOf(app) else { return }
        handler?(.focused(window.snapshot()))
    }

    deinit {
        notificationCenter.removeObserver(self)
    }
}
