import AppKit
import ApplicationServices
import CoreGraphics
import os

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

// Native replacement for hs.window.filter: per-app AXObservers plus NSWorkspace launch/terminate
// surface window created/focused/destroyed events, and allWindows() seeds the model.
final class AXWindowObserver {
    private struct ElementKey: Hashable {
        let element: AXUIElement

        static func == (lhs: ElementKey, rhs: ElementKey) -> Bool { CFEqual(lhs.element, rhs.element) }
        func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
    }

    private struct WindowRef {
        let pid: pid_t
        let id: CGWindowID
    }

    private var handler: ((WindowEvent) -> Void)?
    private var observers: [pid_t: AXObserver] = [:]
    private var applications: [pid_t: NSRunningApplication] = [:]
    private var windowIds: [ElementKey: WindowRef] = [:]
    private let ownPid = ProcessInfo.processInfo.processIdentifier

    func start(_ handler: @escaping (WindowEvent) -> Void) {
        self.handler = handler

        for app in NSWorkspace.shared.runningApplications where observable(app) {
            observe(app)
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(applicationLaunched(_:)),
                           name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(applicationTerminated(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(applicationActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    func allWindows() -> [AXWindow] {
        NSWorkspace.shared.runningApplications
            .filter(observable)
            .flatMap { app in windowElements(pid: app.processIdentifier).map { AXWindow(element: $0, application: app) } }
    }

    func handle(element: AXUIElement, notification: String, observer: AXObserver) {
        switch notification {
        case kAXWindowCreatedNotification:
            guard let app = application(for: element) else {
                Log.observer.debug("dropped \(notification, privacy: .public): unknown application")
                return
            }
            watchForDestruction(element, app: app, observer: observer)
            handler?(.created(AXWindow(element: element, application: app)))
        case kAXFocusedWindowChangedNotification:
            guard let app = application(for: element) else {
                Log.observer.debug("dropped \(notification, privacy: .public): unknown application")
                return
            }
            handler?(.focused(AXWindow(element: element, application: app)))
        case kAXUIElementDestroyedNotification:
            guard let ref = windowIds.removeValue(forKey: ElementKey(element: element)) else {
                Log.observer.debug("dropped \(notification, privacy: .public): element not registered")
                return
            }
            handler?(.destroyed(ref.id))
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

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return }

        var observer: AXObserver?
        let createResult = AXObserverCreate(pid, axObserverCallback, &observer)
        guard createResult == .success, let observer else {
            Log.observer.error("cannot observe pid=\(pid, privacy: .public) app=\(app.localizedName ?? "", privacy: .public) err=\(createResult.rawValue, privacy: .public)")
            return
        }

        applications[pid] = app
        observers[pid] = observer

        let appElement = AXUIElementCreateApplication(pid)
        addNotification(observer, appElement, kAXWindowCreatedNotification, pid: pid)
        addNotification(observer, appElement, kAXFocusedWindowChangedNotification, pid: pid)

        let windows = windowElements(pid: pid)
        Log.observer.info("observing pid=\(pid, privacy: .public) app=\(app.localizedName ?? "", privacy: .public) windows=\(windows.count, privacy: .public)")
        for window in windows {
            watchForDestruction(window, app: app, observer: observer)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func forget(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        applications[pid] = nil
        windowIds = windowIds.filter { $0.value.pid != pid }
    }

    private func watchForDestruction(_ window: AXUIElement, app: NSRunningApplication, observer: AXObserver) {
        let id = AXWindow(element: window, application: app).id
        windowIds[ElementKey(element: window)] = WindowRef(pid: app.processIdentifier, id: id)
        addNotification(observer, window, kAXUIElementDestroyedNotification, pid: app.processIdentifier)
    }

    private func addNotification(_ observer: AXObserver, _ element: AXUIElement, _ notification: String, pid: pid_t) {
        let result = AXObserverAddNotification(observer, element, notification as CFString, Unmanaged.passUnretained(self).toOpaque())
        if result != .success {
            Log.observer.error("addNotification \(notification, privacy: .public) failed pid=\(pid, privacy: .public) err=\(result.rawValue, privacy: .public)")
        }
    }

    private func windowElements(pid: pid_t) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else {
            Log.observer.debug("windowElements failed pid=\(pid, privacy: .public) err=\(result.rawValue, privacy: .public)")
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
        observe(app)
    }

    @objc private func applicationTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        forget(app.processIdentifier)
    }

    @objc private func applicationActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              observable(app),
              let window = focusedWindow(of: app)
        else { return }
        handler?(.focused(window))
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }
}
