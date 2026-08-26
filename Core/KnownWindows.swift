import AppKit
import ApplicationServices
import CoreGraphics

/// The windows OttoWM knows about, and the AX subscriptions that keep them known.
///
/// Holds the map AXUIElement <-> CGWindowID plus pid -> application, and one `AppObserver`
/// per observed application. A window is registered only together with its subscriptions,
/// so a known window reports its own destruction. Nothing here emits a `WindowEvent`: every
/// call returns what changed, and `AXWindowObserver` turns that into events.
final class KnownWindows {
    private struct WindowRef {
        let pid: pid_t
        let id: CGWindowID
    }

    private static let applicationNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
    ]

    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    private var refs: [AXUIElement: WindowRef] = [:]
    private var elementsById: [CGWindowID: AXUIElement] = [:]
    private var applications: [pid_t: NSRunningApplication] = [:]
    private var observers: [pid_t: AppObserver] = [:]

    private let makeObserver: (pid_t, @escaping (AXUIElement, String) -> Void) -> AppObserver?
    private let windowElements: (pid_t) -> [AXUIElement]
    private let makeWindow: (AXUIElement, NSRunningApplication) -> AXWindow
    private let focusedWindow: () -> AXWindow?
    private let focusedWindowOf: (NSRunningApplication) -> AXWindow?
    private let isAlive: (AXUIElement) -> Bool
    private let screenIsLocked: () -> Bool

    init(
        makeObserver: @escaping (pid_t, @escaping (AXUIElement, String) -> Void) -> AppObserver? = AXAppObserver.make,
        windowElements: @escaping (pid_t) -> [AXUIElement] = {
            AXUIElementCreateApplication($0).value(of: .windows) as? [AXUIElement] ?? []
        },
        makeWindow: @escaping (AXUIElement, NSRunningApplication) -> AXWindow = AXWindow.init(element:application:),
        focusedWindow: @escaping () -> AXWindow? = AXWindow.focused,
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
        self.makeObserver = makeObserver
        self.windowElements = windowElements
        self.makeWindow = makeWindow
        self.focusedWindow = focusedWindow
        self.focusedWindowOf = focusedWindowOf
        self.isAlive = isAlive
        self.screenIsLocked = screenIsLocked
    }

    // MARK: - Observing applications

    func isObserving(_ app: NSRunningApplication) -> Bool {
        observers[app.processIdentifier] != nil
    }

    /// Starts observing the application and registers the windows it already lists.
    /// - Parameter notify: called with every AX notification of the application.
    /// - Returns: the windows found and whether the application level subscriptions are in
    ///   place, or `nil` when the application is already observed or has no AX observer.
    func observe(
        _ app: NSRunningApplication,
        notify: @escaping (AXUIElement, String) -> Void
    ) -> (windows: [WindowSnapshot], subscribed: Bool)? {
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return nil }
        guard let observer = makeObserver(pid, notify) else {
            Log.windows.error("cannot observe pid=\(pid) app=\(app.localizedName ?? "")")
            return nil
        }

        add(app)
        observers[pid] = observer

        let observed = subscribe(to: app, observer: observer)
        Log.windows.info("observing pid=\(pid) app=\(app.localizedName ?? "") "
            + "windows=\(observed.windows.count) subscribed=\(observed.subscribed)")

        return observed
    }

    /// Subscribes again to an application that did not answer the first time.
    /// - Returns: the windows not known yet, or `nil` when the application is not observed.
    func resubscribe(to app: NSRunningApplication) -> (windows: [WindowSnapshot], subscribed: Bool)? {
        guard let observer = observers[app.processIdentifier] else { return nil }
        return subscribe(to: app, observer: observer)
    }

    /// Registers the windows of the application that are not known yet.
    func rescan(_ app: NSRunningApplication) -> [WindowSnapshot] {
        guard let observer = observers[app.processIdentifier] else { return [] }

        let elements = unregistered(of: windowElements(app.processIdentifier))
        return watchWindows(of: elements, app: app, observer: observer)
    }

    /// Invalidates the observer of the application and forgets its windows.
    func stopObserving(_ app: NSRunningApplication) {
        guard let observer = observers.removeValue(forKey: app.processIdentifier) else { return }

        observer.invalidate()
        evict(pid: app.processIdentifier)
    }

    // MARK: - Registering windows

    /// The window behind the element, without registering it.
    /// - Returns: `nil` when the element has no window id.
    func window(of element: AXUIElement, in app: NSRunningApplication) -> AXWindow? {
        let window = makeWindow(element, app)
        return window.id != 0 ? window : nil
    }

    /// Registers the window and subscribes it to the window notifications.
    /// - Returns: `nil` when the element has no window id, is already known, or its
    ///   application is not observed.
    func watch(_ element: AXUIElement, of app: NSRunningApplication) -> AXWindow? {
        guard !knows(element),
              let observer = observers[app.processIdentifier],
              let window = window(of: element, in: app)
        else { return nil }

        watchWindow(window, observer: observer)
        return window
    }

    /// Registers the window if it is not known yet.
    /// - Returns: `nil` when the element has no window id.
    func adopt(_ element: AXUIElement, of app: NSRunningApplication) -> AXWindow? {
        guard let window = window(of: element, in: app) else { return nil }

        adopt(window)
        return window
    }

    /// A window that is not the active tab of its group is absent from the application's
    /// window list. Taking the focus is the only moment it can be discovered, so reading
    /// the focused window registers it.
    func adoptFocused() -> AXWindow? {
        guard let window = focusedWindow() else { return nil }

        adopt(window)
        return window
    }

    /// Registers the focused window of the application if it is not known yet.
    /// - Returns: `nil` when the application reports no focused window.
    func adoptFocused(of app: NSRunningApplication) -> AXWindow? {
        guard let window = focusedWindowOf(app) else { return nil }

        adopt(window)
        return window
    }

    /// macOS does not send kAXUIElementDestroyedNotification for every window that dies:
    /// closing a background application's window sends nothing. Probing every known window
    /// finds those.
    /// - Returns: the ids of the windows that no longer answer, now forgotten.
    func dropDead() -> [CGWindowID] {
        guard !screenIsLocked() else { return [] }

        return registered.compactMap { element, id in
            guard !isAlive(element) else { return nil }

            _ = removeWindow(for: element)
            Log.windows.info("window died unannounced id=\(id)")
            return id
        }
    }

    // MARK: - Looking up windows

    func window(for id: CGWindowID) -> AXWindow? {
        guard let element = elementsById[id], let ref = refs[element],
              let app = applications[ref.pid]
        else { return nil }
        return AXWindow(element: element, application: app, id: id)
    }

    func removeWindow(for element: AXUIElement) -> CGWindowID? {
        guard let ref = refs.removeValue(forKey: element) else { return nil }
        removeReverse(ref.id, element)
        return ref.id
    }

    func hasWindows(of app: NSRunningApplication) -> Bool {
        refs.values.contains { $0.pid == app.processIdentifier }
    }

    // MARK: - Private

    private func add(_ app: NSRunningApplication) {
        applications[app.processIdentifier] = app
    }

    /// Every caller filters out the elements already known, so an element is never
    /// registered twice.
    private func register(_ element: AXUIElement, pid: pid_t, id: CGWindowID) {
        refs[element] = WindowRef(pid: pid, id: id)
        elementsById[id] = element
    }

    private func evict(pid: pid_t) {
        applications[pid] = nil
        for (element, ref) in refs where ref.pid == pid {
            refs[element] = nil
            removeReverse(ref.id, element)
        }
    }

    private func knows(_ element: AXUIElement) -> Bool {
        refs[element] != nil
    }

    /// Every registered window, as an element paired with its id.
    /// - Complexity: O(*n*) in the number of registered windows.
    private var registered: [(element: AXUIElement, id: CGWindowID)] {
        refs.map { (element: $0.key, id: $0.value.id) }
    }

    private func unregistered(of elements: [AXUIElement]) -> [AXUIElement] {
        elements.filter { !knows($0) }
    }

    /// Subscribes to the application level notifications and registers the windows it
    /// lists that are not known yet.
    ///
    /// A just launched application may not have its AX interface up yet, hence the
    /// `subscribed` flag: nothing else re-subscribes if these subscriptions fail.
    private func subscribe(
        to app: NSRunningApplication,
        observer: AppObserver
    ) -> (windows: [WindowSnapshot], subscribed: Bool) {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        let subscribed = Self.applicationNotifications
            .map { observer.watch(appElement, $0) }
            .allSatisfy { $0 }

        let elements = unregistered(of: windowElements(pid))

        return (watchWindows(of: elements, app: app, observer: observer), subscribed)
    }

    private func adopt(_ window: AXWindow) {
        guard window.id != 0, !knows(window.element),
              let observer = observers[window.application.processIdentifier]
        else { return }

        Log.windows.info("adopting \(window.logDescription)")
        watchWindow(window, observer: observer)
    }

    private func watchWindows(
        of elements: [AXUIElement],
        app: NSRunningApplication,
        observer: AppObserver
    ) -> [WindowSnapshot] {
        elements
            .map { makeWindow($0, app) }
            .filter { $0.id != 0 }
            .map { window in
                watchWindow(window, observer: observer)
                return window.snapshot()
            }
    }

    private func watchWindow(_ window: AXWindow, observer: AppObserver) {
        register(window.element, pid: window.application.processIdentifier, id: window.id)
        for notification in Self.windowNotifications {
            _ = observer.watch(window.element, notification)
        }
    }

    private func removeReverse(_ id: CGWindowID, _ element: AXUIElement) {
        if elementsById[id] == element { elementsById[id] = nil }
    }

    deinit {
        for observer in observers.values {
            observer.invalidate()
        }
    }
}
