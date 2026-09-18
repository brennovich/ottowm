import AppKit
import ApplicationServices
import CoreGraphics

final class AXWindowEventsHarness {
    let ax = StubAXAccess()
    var elements: [pid_t: [AXUIElement]] = [:] {
        didSet { setApplicationAttribute(.windows, from: oldValue, to: elements) { $0 as NSArray } }
    }
    var focusedElements: [pid_t: AXUIElement] = [:] {
        didSet { setApplicationAttribute(.focusedWindow, from: oldValue, to: focusedElements) { $0 } }
    }
    var failingNotificationPids: Set<pid_t> = []
    var unreadyPids: Set<pid_t> = []
    var deadElements: Set<AXUIElement> = [] {
        didSet {
            for element in oldValue { ax.statuses[element] = nil }
            for element in deadElements { ax.statuses[element] = .invalidUIElement }
        }
    }
    var screenIsLocked = false

    // The start scan subscribes the applications on several threads at once, so what it
    // records is read and written from all of them.
    private let lock = NSLock()
    private var subscriptions: [pid_t: [(element: AXUIElement, notification: String)]] = [:]
    private var notificationCallbacks: [pid_t: (AXUIElement, String) -> Void] = [:]
    private var invalidations: [pid_t] = []

    var subscribed: [pid_t: [(element: AXUIElement, notification: String)]] { locked { subscriptions } }
    var callbacks: [pid_t: (AXUIElement, String) -> Void] { locked { notificationCallbacks } }
    var invalidatedPids: [pid_t] { locked { invalidations } }

    lazy var applications = Applications()

    lazy var windowEvents = AXWindowEvents(
        applications: applications,
        makeNotifications: { pid, callback in
            guard !self.failingNotificationPids.contains(pid) else { return nil }
            self.locked { self.notificationCallbacks[pid] = callback }
            return AXNotifications(
                subscribe: { element, notification in
                    self.locked { self.subscriptions[pid, default: []].append((element, notification)) }
                    return self.unreadyPids.contains(pid) ? .cannotComplete : .success
                },
                invalidate: { self.locked { self.invalidations.append(pid) } }
            )
        },
        access: ax.access,
        screenIsLocked: { self.screenIsLocked }
    )

    func makeElement(id: CGWindowID) -> AXUIElement {
        let element = ax.makeElement()
        ax.windowIds[element] = id
        return element
    }

    @discardableResult
    func addWindow(pid: pid_t, id: CGWindowID) -> AXUIElement {
        let element = makeElement(id: id)
        elements[pid, default: []].append(element)
        return element
    }

    func setFrontmost(_ element: AXUIElement, of app: NSRunningApplication) {
        ax.frontmost = app
        focusedElements[app.processIdentifier] = element
    }

    private func setApplicationAttribute<Value>(
        _ attribute: AXAttribute,
        from old: [pid_t: Value],
        to new: [pid_t: Value],
        _ object: (Value) -> AnyObject
    ) {
        for pid in Set(old.keys).union(new.keys) {
            ax.attributes[AXUIElementCreateApplication(pid), default: [:]][attribute] = new[pid].map(object)
        }
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
    kAXWindowMovedNotification,
    kAXWindowResizedNotification,
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
            case .reframed: "reframed"
            }
        }
    }
}
