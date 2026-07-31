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

// Per-app AXObservers plus NSWorkspace launch/terminate surface window
// created/focused/destroyed events.
final class AXWindowObserver {
    private struct ElementKey: Hashable {
        let element: AXUIElement

        static func == (lhs: ElementKey, rhs: ElementKey) -> Bool { CFEqual(lhs.element, rhs.element) }
        func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
    }

    private var handler: ((WindowEvent) -> Void)?
    private var observers: [pid_t: AXObserver] = [:]
    private var applications: [pid_t: NSRunningApplication] = [:]
    private var registry = ObservedWindowRegistry<ElementKey>()
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
        guard let (key, pid) = registry.element(for: id),
              let app = applications[pid]
        else { return nil }
        return AXWindow(element: key.element, application: app, id: id)
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
            watchForDestruction(window, observer: observer)
            handler?(.created(window.snapshot()))
        case kAXFocusedWindowChangedNotification:
            guard let app = application(for: element) else {
                Log.observer.debug("dropped \(notification): unknown application")
                return
            }
            handler?(.focused(AXWindow(element: element, application: app).snapshot()))
        case kAXUIElementDestroyedNotification:
            guard let id = registry.removeWindow(for: ElementKey(element: element)) else {
                Log.observer.debug("dropped \(notification): element not registered")
                return
            }
            handler?(.destroyed(id))
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
            watchForDestruction(window, observer: observer)

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
        for key in registry.unregistered(of: elements.map { ElementKey(element: $0) }) {
            let axWindow = AXWindow(element: key.element, application: app)
            guard axWindow.id != 0 else { continue }
            Log.observer.info("rescan found window \(axWindow.logDescription)")
            watchForDestruction(axWindow, observer: observer)
            handler?(.created(axWindow.snapshot()))
        }
    }

    private func forget(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        applications[pid] = nil
        registry.evict(pid: pid)
    }

    private func watchForDestruction(_ window: AXWindow, observer: AXObserver) {
        let pid = window.application.processIdentifier
        registry.register(ElementKey(element: window.element), pid: pid, id: window.id)
        addNotification(observer, window.element, kAXUIElementDestroyedNotification, pid: pid)
    }

    private func addNotification(_ observer: AXObserver, _ element: AXUIElement, _ notification: String, pid: pid_t) {
        let result = AXObserverAddNotification(observer, element, notification as CFString, Unmanaged.passUnretained(self).toOpaque())
        if result != .success {
            Log.observer.error("addNotification \(notification) failed pid=\(pid) err=\(result.rawValue)")
        }
    }

    private func windowElements(pid: pid_t) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else {
            Log.observer.debug("windowElements failed pid=\(pid) err=\(result.rawValue)")
            return []
        }
        return windows
    }

    private func application(for element: AXUIElement) -> NSRunningApplication? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return applications[pid] ?? NSRunningApplication(processIdentifier: pid)
    }

    private func focusedWindow(of app: NSRunningApplication) -> AXWindow? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value
        else { return nil }
        return AXWindow(element: window as! AXUIElement, application: app)
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
        guard let window = focusedWindow(of: app) else { return }
        handler?(.focused(window.snapshot()))
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }
}
