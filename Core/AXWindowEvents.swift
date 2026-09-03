import AppKit
import ApplicationServices
import CoreGraphics

final class AXWindowEvents {
    /// What a scan answers with. `windows` are the snapshots it hands over and `focused`
    /// the window that took the focus, kept apart so the caller can announce it as such.
    struct Attempt {
        let windows: [WindowSnapshot]
        let focused: WindowSnapshot?
        let subscription: Subscription.Outcome

        var all: [WindowSnapshot] { windows + (focused.map { [$0] } ?? []) }
    }

    var onEvent: ((WindowEvent) -> Void)?

    private let applications: Applications
    private let makeNotifications: (pid_t, @escaping (AXUIElement, String) -> Void) -> AXNotifications?
    private let makeWindow: (AXUIElement, NSRunningApplication) -> AXWindow
    private let isAlive: (AXWindow) -> Bool
    private let screenIsLocked: () -> Bool
    private var suspected: Set<AXWindow> = []

    init(
        applications: Applications,
        makeNotifications: @escaping (pid_t, @escaping (AXUIElement, String) -> Void) -> AXNotifications?
            = AXNotifications.of,
        makeWindow: @escaping (AXUIElement, NSRunningApplication) -> AXWindow
            = AXWindow.init(element:application:),
        isAlive: @escaping (AXWindow) -> Bool = { window in
            var value: CFTypeRef?
            return trace(.read, AXAttribute.role.rawValue) {
                AXUIElementCopyAttributeValue(window.element, AXAttribute.role.rawValue as CFString, &value)
            } != .invalidUIElement
        },
        screenIsLocked: @escaping () -> Bool = { false }
    ) {
        self.applications = applications
        self.makeNotifications = makeNotifications
        self.makeWindow = makeWindow
        self.isAlive = isAlive
        self.screenIsLocked = screenIsLocked
    }

    func start(_ app: NSRunningApplication) -> Attempt? {
        let pid = app.processIdentifier
        guard applications.find(by: pid) == nil else { return nil }
        let notify = { [weak self] (element: AXUIElement, notification: String) in
            guard let self else { return }
            handle(element, notification, of: app)
        }
        guard let notifications = makeNotifications(pid, notify) else {
            Log.windows.error("cannot subscribe pid=\(pid) app=\(app.localizedName ?? "")")
            return nil
        }

        let application = Application(app, channel: notifications)

        let attempt = attempt(of: applications.add(application))
        Log.windows.info("started pid=\(pid) app=\(application.name) "
            + "windows=\(attempt.all.count) subscription=\(attempt.subscription.rawValue)")

        return attempt
    }

    func stop(_ app: NSRunningApplication) {
        applications.remove(by: app.processIdentifier)
    }

    func discover(_ app: NSRunningApplication) -> Attempt? {
        guard let application = applications.find(by: app.processIdentifier) else { return nil }

        return attempt(of: applications.add(application))
    }

    /// Answers with every window the application holds, the ones already attached and the
    /// focused one included. Window events are dropped while the screen is locked, so the
    /// registry and the workspaces drift apart behind the login window, and only a full
    /// read closes the gap.
    func inventory(_ app: NSRunningApplication) -> Attempt? {
        guard let application = applications.find(by: app.processIdentifier) else { return nil }

        let added = applications.add(application)
        return Attempt(
            windows: application.windows.map { $0.snapshot() },
            focused: nil,
            subscription: added.subscription
        )
    }

    /// A window is reported dead only after two passes without an answer. A single read
    /// fails for a window that is alive: the sweep runs the moment the screen unlocks,
    /// where an application still coming back from sleep answers for none of its windows.
    func sweepDeadWindows() {
        guard !screenIsLocked() else { return }

        var confirmed: [CGWindowID] = []
        var stillSuspected: Set<AXWindow> = []

        for application in applications.all {
            for window in application.windows where !isAlive(window) {
                guard suspected.contains(window) else {
                    stillSuspected.insert(window)
                    continue
                }
                if let id = application.detach(window)?.id { confirmed.append(id) }
            }
        }

        suspected = stillSuspected
        for windowId in confirmed {
            Log.windows.info("window died unannounced id=\(windowId)")
            onEvent?(.destroyed(windowId))
        }
    }

    private func handle(_ element: AXUIElement, _ notification: String, of app: NSRunningApplication) {
        guard let owner = applications.find(by: app.processIdentifier),
              let event = event(for: makeWindow(element, owner.running), notification: notification, of: owner)
        else {
            Log.windows.debug("dropped \(notification)")
            return
        }

        onEvent?(event)
    }

    private func event(
        for window: AXWindow,
        notification: String,
        of app: Application
    ) -> WindowEvent? {
        switch notification {
        case kAXWindowCreatedNotification:
            guard case let .attached(attached) = app.attach(window) else { return nil }
            return .created(attached.snapshot())
        case kAXFocusedWindowChangedNotification:
            // A window already attached is reported again, from the registry: a repeated
            // focus is an event, and the stored window has its id without a read.
            return app.attach(window).window.map { .focused($0.snapshot()) }
        case kAXUIElementDestroyedNotification:
            return app.detach(window).map { WindowEvent.destroyed($0.id) }
        case kAXWindowMiniaturizedNotification:
            return app.findWindow(window).map { .minimized($0.id) }
        case kAXWindowDeminiaturizedNotification:
            return app.findWindow(window).map { .unminimized($0.snapshot()) }
        default:
            return nil
        }
    }

    private func attempt(of added: Applications.AddedResult) -> Attempt {
        Attempt(
            windows: added.windows.map { $0.snapshot() },
            focused: added.focused?.snapshot(),
            subscription: added.subscription
        )
    }
}
