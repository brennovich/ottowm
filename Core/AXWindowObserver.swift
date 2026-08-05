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
    private let registry: WindowRegistry
    private var handler: ((WindowEvent) -> Void)?
    private var observers: [pid_t: AXObserver] = [:]
    private let ownPid = ProcessInfo.processInfo.processIdentifier

    init(registry: WindowRegistry) {
        self.registry = registry
        registry.adopt = { [weak self] in self?.adopt($0) }
    }

    // Returns the windows discovered while registering the observers, so the caller
    // can seed the model with them instead of sweeping every application again.
    func start(_ handler: @escaping (WindowEvent) -> Void) -> [WindowSnapshot] {
        self.handler = handler

        let windows = NSWorkspace.shared.runningApplications
            .filter(observable)
            .flatMap { observe($0) }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(applicationLaunched(_:)),
                           name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(applicationTerminated(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(applicationActivated(_:)),
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

    func handle(element: AXUIElement, notification: String, observer: AXObserver) {
        guard let event = event(for: element, notification: notification, observer: observer) else {
            Log.observer.debug("dropped \(notification)")
            return
        }
        handler?(event)
    }

    private func event(for element: AXUIElement, notification: String, observer: AXObserver) -> WindowEvent? {
        switch notification {
        case kAXWindowCreatedNotification:
            return window(of: element).map { window in
                watchWindow(window, observer: observer)
                return .created(window.snapshot())
            }
        case kAXFocusedWindowChangedNotification:
            return application(for: element).map { app in
                let window = AXWindow(element: element, application: app)
                adopt(window)
                return .focused(window.snapshot())
            }
        case kAXUIElementDestroyedNotification:
            return registry.removeWindow(for: element).map(WindowEvent.destroyed)
        case kAXWindowMiniaturizedNotification:
            return window(of: element).map { .minimized($0.id) }
        case kAXWindowDeminiaturizedNotification:
            return window(of: element).map { .unminimized($0.snapshot()) }
        default:
            return nil
        }
    }

    private func observable(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.processIdentifier != ownPid
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

        registry.add(app)
        observers[pid] = observer

        let appElement = AXUIElementCreateApplication(pid)
        addNotification(observer, appElement, kAXWindowCreatedNotification, pid: pid)
        addNotification(observer, appElement, kAXFocusedWindowChangedNotification, pid: pid)

        let elements = windowElements(pid: pid)
        Log.observer.info("observing pid=\(pid) app=\(app.localizedName ?? "") windows=\(elements.count)")

        let windows = watchWindows(of: elements, app: app, observer: observer)
        if emitExistingWindows {
            windows.forEach { handler?(.created($0)) }
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        return windows
    }

    private func watchWindows(of elements: [AXUIElement], app: NSRunningApplication, observer: AXObserver) -> [WindowSnapshot] {
        elements
            .map { AXWindow(element: $0, application: app) }
            .filter { $0.id != 0 }
            .map { window in
                watchWindow(window, observer: observer)
                return window.snapshot()
            }
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
        axPid(element).flatMap { registry.application(for: $0) ?? NSRunningApplication(processIdentifier: $0) }
    }

    @objc private func applicationLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              observable(app)
        else { return }
        observe(app, emitExistingWindows: true)
    }

    @objc private func applicationTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        
        let pid = app.processIdentifier
        
        guard let observer = observers.removeValue(forKey: pid) else { return }
        
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        registry.evict(pid: pid)
    }

    @objc private func applicationActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              observable(app)
        else { return }
        let pid = app.processIdentifier
        guard let observer = observers[pid] else { return }

        let elements = registry.unregistered(of: windowElements(pid: pid))
        for snapshot in watchWindows(of: elements, app: app, observer: observer) {
            Log.observer.info("rescan found window \(snapshot.logDescription)")
            handler?(.created(snapshot))
        }
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
