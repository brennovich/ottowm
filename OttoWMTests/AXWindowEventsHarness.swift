import AppKit
import ApplicationServices
import CoreGraphics

final class AXWindowEventsHarness {
    var elements: [pid_t: [AXUIElement]] = [:]
    var windowIds: [AXUIElement: CGWindowID] = [:]
    var focusedElements: [pid_t: AXUIElement] = [:]
    var failingNotificationPids: Set<pid_t> = []
    var unreadyPids: Set<pid_t> = []
    var unsupportedPids: Set<pid_t> = []
    var deadElements: Set<AXUIElement> = []
    var screenIsLocked = false
    var onSubscribe: (() -> Void)?

    // The start scan subscribes the applications on several threads at once, so what it
    // records is read and written from all of them.
    private let lock = NSLock()
    private var subscriptions: [pid_t: [(element: AXUIElement, notification: String)]] = [:]
    private var notificationCallbacks: [pid_t: (AXUIElement, String) -> Void] = [:]
    private var invalidations: [pid_t] = []
    private var listings: [pid_t] = []
    private var built: [AXUIElement] = []

    private var nextElementToken: pid_t = 5000

    var subscribed: [pid_t: [(element: AXUIElement, notification: String)]] { locked { subscriptions } }
    var callbacks: [pid_t: (AXUIElement, String) -> Void] { locked { notificationCallbacks } }
    var invalidatedPids: [pid_t] { locked { invalidations } }
    var listedPids: [pid_t] { locked { listings } }
    var builtElements: [AXUIElement] { locked { built } }

    lazy var applications = Applications(
        focusedWindow: { self.focusedWindow(of: $0) },
        listedWindows: { app in
            let pid = app.processIdentifier
            self.locked { self.listings.append(pid) }
            return (self.elements[pid] ?? []).map { self.window($0, of: app) }
        }
    )

    lazy var windowEvents = AXWindowEvents(
        applications: applications,
        makeNotifications: { pid, callback in
            guard !self.failingNotificationPids.contains(pid) else { return nil }
            self.locked { self.notificationCallbacks[pid] = callback }
            return AXNotifications(
                subscribe: { element, notification in
                    self.onSubscribe?()
                    self.locked { self.subscriptions[pid, default: []].append((element, notification)) }
                    if self.unsupportedPids.contains(pid) { return .notificationUnsupported }
                    return self.unreadyPids.contains(pid) ? .cannotComplete : .success
                },
                invalidate: { self.locked { self.invalidations.append(pid) } }
            )
        },
        makeWindow: { element, app in
            self.locked { self.built.append(element) }
            return self.window(element, of: app)
        },
        isAlive: { !self.deadElements.contains($0.element) },
        screenIsLocked: { self.screenIsLocked }
    )

    func window(_ element: AXUIElement, of app: NSRunningApplication) -> AXWindow {
        AXWindow(element: element, application: app, id: windowIds[element] ?? 0)
    }

    func focusedWindow(of app: NSRunningApplication) -> AXWindow? {
        focusedElements[app.processIdentifier].map { window($0, of: app) }
    }

    func makeElement(id: CGWindowID) -> AXUIElement {
        let element = AXUIElementCreateApplication(nextElementToken)
        nextElementToken += 1
        windowIds[element] = id
        return element
    }

    @discardableResult
    func addWindow(pid: pid_t, id: CGWindowID) -> AXUIElement {
        let element = makeElement(id: id)
        elements[pid, default: []].append(element)
        return element
    }

    func appNotificationCount(pid: pid_t) -> Int {
        subscribed[pid]?.filter { $0.notification == kAXWindowCreatedNotification }.count ?? 0
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

let windowNotifications = [
    kAXUIElementDestroyedNotification,
    kAXWindowMiniaturizedNotification,
    kAXWindowDeminiaturizedNotification,
]

let applicationNotifications = [
    kAXWindowCreatedNotification,
    kAXFocusedWindowChangedNotification,
]

extension [WindowEvent] {
    var descriptions: [String] {
        map {
            switch $0 {
            case let .created(win): "created(\(win.id))"
            case let .focused(win): "focused(\(win.id))"
            case let .destroyed(id): "destroyed(\(id))"
            case let .minimized(id): "minimized(\(id))"
            case let .unminimized(win): "unminimized(\(win.id))"
            }
        }
    }
}
