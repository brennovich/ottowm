import AppKit
import ApplicationServices
import CoreGraphics

private let subscriptionRetryDelay: TimeInterval = 0.1
private let lockScreenBundleId = "com.apple.loginwindow"

/// Turns per-application `AXObserver`s and `NSWorkspace` notifications into `WindowEvent`s:
/// created, focused, destroyed, minimized and unminimized.
final class AXWindowObserver {
    private let registry: WindowRegistry
    private let focusedWindow: () -> AXWindow?
    private let makeObserver: (pid_t, @escaping (AXUIElement, String) -> Void) -> AppObserver?
    private let scheduleRetry: (@escaping () -> Void) -> Void
    private let now: () -> Date
    private let notificationCenter: NotificationCenter
    private let runningApplications: () -> [NSRunningApplication]
    private let windowElements: (pid_t) -> [AXUIElement]
    private let makeWindow: (AXUIElement, NSRunningApplication) -> AXWindow
    private let focusedWindowOf: (NSRunningApplication) -> AXWindow?
    private let isAlive: (AXUIElement) -> Bool
    private let screenIsLocked: () -> Bool
    private var handler: ((WindowEvent) -> Void)?
    private var observers: [pid_t: AppObserver] = [:]
    private let ownPid = ProcessInfo.processInfo.processIdentifier

    /// A freshly launched application can take seconds to answer AX, and announces no
    /// window until it does, hence the retries. An application that fails every retry is
    /// given up on; it may have no AX interface.
    static let subscriptionGracePeriod: TimeInterval = 15

    private static let applicationNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
    ]

    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    private static let workspaceNotifications: [(name: NSNotification.Name, selector: Selector)] = [
        (NSWorkspace.didLaunchApplicationNotification, #selector(applicationLaunched(_:))),
        (NSWorkspace.didTerminateApplicationNotification, #selector(applicationTerminated(_:))),
        (NSWorkspace.didActivateApplicationNotification, #selector(applicationActivated(_:))),
    ]

    init(
        registry: WindowRegistry,
        focusedWindow: @escaping () -> AXWindow? = AXWindow.focused,
        makeObserver: @escaping (pid_t, @escaping (AXUIElement, String) -> Void) -> AppObserver? = AXAppObserver.make,
        scheduleRetry: @escaping (@escaping () -> Void) -> Void = { work in
            DispatchQueue.main.asyncAfter(deadline: .now() + subscriptionRetryDelay, execute: work)
        },
        now: @escaping () -> Date = Date.init,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        runningApplications: @escaping () -> [NSRunningApplication] = { NSWorkspace.shared.runningApplications },
        windowElements: @escaping (pid_t) -> [AXUIElement] = {
            AXUIElementCreateApplication($0).value(of: .windows) as? [AXUIElement] ?? []
        },
        makeWindow: @escaping (AXUIElement, NSRunningApplication) -> AXWindow = AXWindow.init(element:application:),
        focusedWindowOf: @escaping (NSRunningApplication) -> AXWindow? = AXWindow.focused(of:),
        // Only an element the application has released returns invalidUIElement. A slow
        // or briefly unreachable window fails with another error, so anything but
        // invalidUIElement counts as alive.
        isAlive: @escaping (AXUIElement) -> Bool = { element in
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, AXAttribute.role.rawValue as CFString, &value) != .invalidUIElement
        },
        screenIsLocked: @escaping () -> Bool = { false }
    ) {
        self.registry = registry
        self.focusedWindow = focusedWindow
        self.makeObserver = makeObserver
        self.scheduleRetry = scheduleRetry
        self.now = now
        self.notificationCenter = notificationCenter
        self.runningApplications = runningApplications
        self.windowElements = windowElements
        self.makeWindow = makeWindow
        self.focusedWindowOf = focusedWindowOf
        self.isAlive = isAlive
        self.screenIsLocked = screenIsLocked
    }

    /// macOS does not send kAXUIElementDestroyedNotification for every window that dies:
    /// closing a background application's window sends nothing. Probing every known window
    /// finds those. Called when an application comes to front and when the screen unlocks,
    /// the two moments a stale entry starts to matter.
    func dropDeadWindows() {
        guard !screenIsLocked() else { return }

        for (element, id) in registry.knownWindows where !isAlive(element) {
            _ = registry.removeWindow(for: element)
            Log.observer.info("window died unannounced id=\(id)")
            handler?(.destroyed(id))
        }
    }

    /// A window that is not the active tab of its group is absent from the application's
    /// window list. Taking the focus is the only moment it can be discovered. Adopting it
    /// registers the window and subscribes it to the lifecycle notifications.
    func adoptFocusedWindow() -> AXWindow? {
        guard let window = focusedWindow() else { return nil }
        adopt(window)
        return window
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

    private func adopt(_ window: AXWindow) {
        guard window.id != 0, !registry.knows(window.element),
              let observer = observers[window.application.processIdentifier]
        else { return }

        Log.observer.info("adopting \(window.logDescription)")
        watchWindow(window, observer: observer)
    }

    private func event(for element: AXUIElement, notification: String, app: NSRunningApplication) -> WindowEvent? {
        switch notification {
        case kAXWindowCreatedNotification:
            guard let observer = observers[app.processIdentifier] else { return nil }
            return window(of: element, app: app).map { window in
                watchWindow(window, observer: observer)
                return .created(window.snapshot())
            }
        case kAXFocusedWindowChangedNotification:
            return window(of: element, app: app).map { window in
                adopt(window)
                return .focused(window.snapshot())
            }
        case kAXUIElementDestroyedNotification:
            return registry.removeWindow(for: element).map(WindowEvent.destroyed)
        case kAXWindowMiniaturizedNotification:
            return window(of: element, app: app).map { .minimized($0.id) }
        case kAXWindowDeminiaturizedNotification:
            return window(of: element, app: app).map { .unminimized($0.snapshot()) }
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
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return [] }
        guard let observer = makeObserver(pid, { [weak self] element, notification in
            guard let self else { return }
            guard let event = event(for: element, notification: notification, app: app) else {
                Log.observer.debug("dropped \(notification)")
                return
            }
            handler?(event)
        }) else {
            Log.observer.error("cannot observe pid=\(pid) app=\(app.localizedName ?? "")")
            return []
        }

        registry.add(app)
        observers[pid] = observer

        return subscribe(to: app, observer: observer, deadline: now().addingTimeInterval(Self.subscriptionGracePeriod))
    }

    /// Subscribes to the application level notifications.
    ///
    /// A just launched application may not have its AX interface up yet, hence the retry.
    /// Nothing else re-subscribes if these subscriptions fail.
    /// - Returns: the windows the application already has.
    private func subscribe(to app: NSRunningApplication, observer: AppObserver, deadline: Date) -> [WindowSnapshot] {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        let subscribed = Self.applicationNotifications
            .map { observer.watch(appElement, $0) }
            .allSatisfy { $0 }

        let elements = registry.unregistered(of: windowElements(pid))
        Log.observer.info("observing pid=\(pid) app=\(app.localizedName ?? "") windows=\(elements.count) subscribed=\(subscribed)")

        if !subscribed {
            retrySubscription(to: app, deadline: deadline)
        }

        return watchWindows(of: elements, app: app, observer: observer)
    }

    private func retrySubscription(to app: NSRunningApplication, deadline: Date) {
        guard now() < deadline else {
            Log.observer.error(
                "giving up on pid=\(app.processIdentifier) app=\(app.localizedName ?? ""): "
                    + "unreachable for \(Int(Self.subscriptionGracePeriod))s"
            )
            return
        }

        scheduleRetry { [weak self] in
            guard let self, let observer = observers[app.processIdentifier] else { return }
            for snapshot in subscribe(to: app, observer: observer, deadline: deadline) {
                Log.observer.info("retry found window \(snapshot.logDescription)")
                handler?(.created(snapshot))
            }
        }
    }

    private func watchWindows(of elements: [AXUIElement], app: NSRunningApplication, observer: AppObserver) -> [WindowSnapshot] {
        elements
            .map { makeWindow($0, app) }
            .filter { $0.id != 0 }
            .map { window in
                watchWindow(window, observer: observer)
                return window.snapshot()
            }
    }

    private func watchWindow(_ window: AXWindow, observer: AppObserver) {
        registry.register(window.element, pid: window.application.processIdentifier, id: window.id)
        for notification in Self.windowNotifications {
            _ = observer.watch(window.element, notification)
        }
    }

    private func window(of element: AXUIElement, app: NSRunningApplication) -> AXWindow? {
        let window = makeWindow(element, app)
        return window.id != 0 ? window : nil
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
        guard let app = app(from: notification),
              let observer = observers.removeValue(forKey: app.processIdentifier)
        else { return }

        observer.invalidate()
        registry.evict(pid: app.processIdentifier)
    }

    @objc private func applicationActivated(_ notification: Notification) {
        guard let app = app(from: notification), canObserve(app),
              let observer = observers[app.processIdentifier]
        else { return }

        dropDeadWindows()

        let elements = registry.unregistered(of: windowElements(app.processIdentifier))
        for snapshot in watchWindows(of: elements, app: app, observer: observer) {
            Log.observer.info("rescan found window \(snapshot.logDescription)")
            handler?(.created(snapshot))
        }
        guard let window = focusedWindowOf(app) else { return }
        handler?(.focused(window.snapshot()))
    }

    deinit {
        notificationCenter.removeObserver(self)
        for observer in observers.values {
            observer.invalidate()
        }
    }
}
