import AppKit
import ApplicationServices
import CoreGraphics

// The C-convention AXObserver callback: trampolines back to the AXWindowObserver carried in refcon.
private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let windowObserver = Unmanaged<AXWindowObserver>.fromOpaque(refcon).takeUnretainedValue()
    windowObserver.handle(element: element, notification: notification as String, observer: observer)
}

// Per-app AXObservers plus NSWorkspace launch/terminate surface the window
// lifecycle events: created, focused, destroyed and (de)minimized.
final class AXWindowObserver {
    // Which AX elements are already watched for destruction, and which window id
    // each one maps to once the element itself can no longer answer (a destroyed
    // element has no attributes).
    struct Registry {
        private struct WindowRef {
            let pid: pid_t
            let id: CGWindowID
        }

        private var refs: [AXUIElement: WindowRef] = [:]
        private var elementsById: [CGWindowID: AXUIElement] = [:]

        mutating func register(_ element: AXUIElement, pid: pid_t, id: CGWindowID) {
            if let previous = refs[element] {
                removeReverse(previous.id, element)
            }
            refs[element] = WindowRef(pid: pid, id: id)
            elementsById[id] = element
        }

        mutating func removeWindow(for element: AXUIElement) -> CGWindowID? {
            guard let ref = refs.removeValue(forKey: element) else { return nil }
            removeReverse(ref.id, element)
            return ref.id
        }

        mutating func evict(pid: pid_t) {
            for (element, ref) in refs where ref.pid == pid {
                refs[element] = nil
                removeReverse(ref.id, element)
            }
        }

        func unregistered(of elements: [AXUIElement]) -> [AXUIElement] {
            elements.filter { refs[$0] == nil }
        }

        func element(for id: CGWindowID) -> (element: AXUIElement, pid: pid_t)? {
            guard let element = elementsById[id], let ref = refs[element] else { return nil }
            return (element, ref.pid)
        }

        private mutating func removeReverse(_ id: CGWindowID, _ element: AXUIElement) {
            if elementsById[id] == element { elementsById[id] = nil }
        }
    }

    private var handler: ((WindowEvent) -> Void)?
    private var observers: [pid_t: AXObserver] = [:]
    private var applications: [pid_t: NSRunningApplication] = [:]
    private var registry = Registry()
    private let ownPid = ProcessInfo.processInfo.processIdentifier

    // Returns the windows discovered while registering the observers, so the caller
    // can seed the model with them instead of sweeping every application again.
    func start(_ handler: @escaping (WindowEvent) -> Void) -> [WindowSnapshot] {
        self.handler = handler

        var windows: [WindowSnapshot] = []
        for app in NSWorkspace.shared.runningApplications where observable(app) {
            windows += observe(app)
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(applicationLaunched(_:)),
                           name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(applicationTerminated(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(applicationActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)

        return windows
    }

    // Resolves a window id through the registry instead of sweeping every app's
    // windows over AX (each sweep is one IPC round trip per running app).
    func window(byId id: CGWindowID) -> AXWindow? {
        guard let (element, pid) = registry.element(for: id),
              let app = applications[pid]
        else { return nil }
        return AXWindow(element: element, application: app, id: id)
    }

    func handle(element: AXUIElement, notification: String, observer: AXObserver) {
        switch notification {
        case kAXWindowCreatedNotification:
            guard let app = application(for: element) else {
                Log.observer.debug("dropped \(notification): unknown application")
                return
            }
            let window = AXWindow(element: element, application: app)
            guard window.id != 0 else {
                Log.observer.debug("dropped \(notification): no window id")
                return
            }
            watchWindow(window, observer: observer)
            handler?(.created(window.snapshot()))
        case kAXFocusedWindowChangedNotification:
            guard let app = application(for: element) else {
                Log.observer.debug("dropped \(notification): unknown application")
                return
            }
            handler?(.focused(AXWindow(element: element, application: app).snapshot()))
        case kAXUIElementDestroyedNotification:
            guard let id = registry.removeWindow(for: element) else {
                Log.observer.debug("dropped \(notification): element not registered")
                return
            }
            handler?(.destroyed(id))
        case kAXWindowMiniaturizedNotification:
            guard let window = window(of: element) else {
                Log.observer.debug("dropped \(notification): unknown window")
                return
            }
            handler?(.minimized(window.id))
        case kAXWindowDeminiaturizedNotification:
            guard let window = window(of: element) else {
                Log.observer.debug("dropped \(notification): unknown window")
                return
            }
            handler?(.unminimized(window.snapshot()))
        default:
            break
        }
    }

    private func observable(_ app: NSRunningApplication) -> Bool {
        shouldObserveApplication(
            activationPolicy: app.activationPolicy,
            pid: app.processIdentifier,
            ownPid: ownPid
        )
    }

    @discardableResult
    private func observe(_ app: NSRunningApplication, emitExistingWindows: Bool = false) -> [WindowSnapshot] {
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return [] }

        var observer: AXObserver?
        let createResult = AXObserverCreate(pid, axObserverCallback, &observer)
        guard createResult == .success, let observer else {
            Log.observer.error("cannot observe pid=\(pid) app=\(app.localizedName ?? "") err=\(createResult.rawValue)")
            return []
        }

        applications[pid] = app
        observers[pid] = observer

        let appElement = AXUIElementCreateApplication(pid)
        addNotification(observer, appElement, kAXWindowCreatedNotification, pid: pid)
        addNotification(observer, appElement, kAXFocusedWindowChangedNotification, pid: pid)

        let elements = windowElements(pid: pid)
        Log.observer.info("observing pid=\(pid) app=\(app.localizedName ?? "") windows=\(elements.count)")

        var windows: [WindowSnapshot] = []
        for element in elements {
            let window = AXWindow(element: element, application: app)
            guard window.id != 0 else { continue }
            watchWindow(window, observer: observer)

            let snapshot = window.snapshot()
            windows.append(snapshot)
            if emitExistingWindows {
                handler?(.created(snapshot))
            }
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        return windows
    }

    // Windows can appear without kAXWindowCreated ever firing: apps restore them
    // around launch before registration lands, or registration fails while the app
    // is still starting. Activation is the moment to sweep for the ones we missed.
    private func rescanWindows(of app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard let observer = observers[pid] else { return }

        let elements = windowElements(pid: pid)
        for element in registry.unregistered(of: elements) {
            let axWindow = AXWindow(element: element, application: app)
            guard axWindow.id != 0 else { continue }
            Log.observer.info("rescan found window \(axWindow.logDescription)")
            watchWindow(axWindow, observer: observer)
            handler?(.created(axWindow.snapshot()))
        }
    }

    private func forget(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        applications[pid] = nil
        registry.evict(pid: pid)
    }

    private func watchWindow(_ window: AXWindow, observer: AXObserver) {
        let pid = window.application.processIdentifier
        registry.register(window.element, pid: pid, id: window.id)
        for notification in [
            kAXUIElementDestroyedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification,
        ] {
            addNotification(observer, window.element, notification, pid: pid)
        }
    }

    private func window(of element: AXUIElement) -> AXWindow? {
        guard let app = application(for: element) else { return nil }
        let window = AXWindow(element: element, application: app)
        return window.id != 0 ? window : nil
    }

    private func addNotification(_ observer: AXObserver, _ element: AXUIElement, _ notification: String, pid: pid_t) {
        let result = AXObserverAddNotification(observer, element, notification as CFString, Unmanaged.passUnretained(self).toOpaque())
        if result != .success {
            Log.observer.error("addNotification \(notification) failed pid=\(pid) err=\(result.rawValue)")
        }
    }

    private func windowElements(pid: pid_t) -> [AXUIElement] {
        axAttribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    private func application(for element: AXUIElement) -> NSRunningApplication? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return applications[pid] ?? NSRunningApplication(processIdentifier: pid)
    }

    @objc private func applicationLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              observable(app)
        else { return }
        observe(app, emitExistingWindows: true)
    }

    @objc private func applicationTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        forget(app.processIdentifier)
    }

    @objc private func applicationActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              observable(app)
        else { return }
        rescanWindows(of: app)
        guard let window = AXWindow.focused(of: app) else { return }
        handler?(.focused(window.snapshot()))
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }
}
