import AppKit
import ApplicationServices
import CoreGraphics

private let subscriptionRetryDelay: TimeInterval = 0.1
private let lockScreenBundleId = "com.apple.loginwindow"

// Per-app AXObservers plus NSWorkspace launch/terminate surface the window
// lifecycle events: created, focused, destroyed and (de)minimized.
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

    // A freshly launched application can take seconds before its AX interface responds,
    // and until then its windows are never announced, hence the retries. One that fails
    // every retry is ignored; it may have no AX interface at all.
    static let subscriptionWindow: TimeInterval = 15

    private static let applicationNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
    ]

    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
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
        // Only an element the application has actually released returns invalidUIElement.
        // A window that is merely slow or momentarily unreachable fails with some other
        // error, so anything but invalidUIElement counts as alive.
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

    // kAXUIElementDestroyedNotification is not delivered for every window that dies: the
    // close button of a window whose application is not in front removes it silently.
    // Probing every known window catches those, and is done when a stale entry is about
    // to matter: an application coming to front, the screen unlocking.
    func dropDeadWindows() {
        guard !screenIsLocked() else { return }

        for (element, id) in registry.knownWindows() where !isAlive(element) {
            _ = registry.removeWindow(for: element)
            Log.observer.info("window died unannounced id=\(id)")
            handler?(.destroyed(id))
        }
    }

    // A window that is not the active tab of its group is absent from the application's
    // window list, so becoming focused is the only moment it can be discovered. Adopting
    // it makes it placeable and subscribes it to the lifecycle notifications.
    func adoptFocusedWindow() -> AXWindow? {
        guard let window = focusedWindow() else { return nil }
        adopt(window)
        return window
    }

    // Returns the windows discovered while registering the observers, so the caller
    // can seed the model with them instead of sweeping every application again.
    func start(_ handler: @escaping (WindowEvent) -> Void) -> [WindowSnapshot] {
        self.handler = handler

        let windows = runningApplications()
            .filter(observable)
            .flatMap { observe($0) }

        notificationCenter.addObserver(self, selector: #selector(applicationLaunched(_:)),
                                       name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(applicationTerminated(_:)),
                                       name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(applicationActivated(_:)),
                                       name: NSWorkspace.didActivateApplicationNotification, object: nil)

        return windows
    }

    private func adopt(_ window: AXWindow) {
        guard window.id != 0, !registry.knows(window.element),
              let observer = observers[window.application.processIdentifier]
        else { return }

        Log.observer.info("adopting \(window.logDescription)")
        watchWindow(window, observer: observer)
    }

    private func handle(element: AXUIElement, notification: String, app: NSRunningApplication) {
        guard let event = event(for: element, notification: notification, app: app) else {
            Log.observer.debug("dropped \(notification)")
            return
        }
        handler?(event)
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

    // The login window comes and goes with the lock screen and covers the whole display.
    // Managed, it would be parked in the corner the moment the user came back.
    private func observable(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.processIdentifier != ownPid
            && app.bundleIdentifier != lockScreenBundleId
    }

    private func observe(_ app: NSRunningApplication) -> [WindowSnapshot] {
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return [] }
        guard let observer = makeObserver(pid, { [weak self] element, notification in
            self?.handle(element: element, notification: notification, app: app)
        }) else {
            Log.observer.error("cannot observe pid=\(pid) app=\(app.localizedName ?? "")")
            return []
        }

        registry.add(app)
        observers[pid] = observer

        return subscribe(to: app, observer: observer, deadline: now().addingTimeInterval(Self.subscriptionWindow))
    }

    // A just launched application has no AX interface yet: the subscriptions fail and its
    // window list comes back empty. Nothing else retries the application level
    // notifications, so without this it stays silent for the rest of its life and the
    // window it opens on launch is never announced.
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
                    + "unreachable for \(Int(Self.subscriptionWindow))s"
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
        guard let app = app(from: notification), observable(app) else { return }
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
        guard let app = app(from: notification), observable(app),
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
