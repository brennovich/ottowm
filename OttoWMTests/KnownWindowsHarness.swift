import AppKit
import ApplicationServices
import CoreGraphics

final class KnownWindowsHarness {
    var elements: [pid_t: [AXUIElement]] = [:]
    var windowIds: [AXUIElement: CGWindowID] = [:]
    var systemFocusedWindow: AXWindow?
    var focusedElements: [pid_t: AXUIElement] = [:]
    var failingObserverPids: Set<pid_t> = []
    var unreadyPids: Set<pid_t> = []
    var deadElements: Set<AXUIElement> = []
    var screenIsLocked = false

    private(set) var watched: [pid_t: [(element: AXUIElement, notification: String)]] = [:]
    private(set) var callbacks: [pid_t: (AXUIElement, String) -> Void] = [:]
    private(set) var invalidatedPids: [pid_t] = []

    private var nextElementToken: pid_t = 5000

    lazy var knownWindows = KnownWindows(
        makeObserver: { pid, callback in
            guard !self.failingObserverPids.contains(pid) else { return nil }
            self.callbacks[pid] = callback
            return AppObserver(
                watch: {
                    self.watched[pid, default: []].append(($0, $1))
                    return !self.unreadyPids.contains(pid)
                },
                invalidate: { self.invalidatedPids.append(pid) }
            )
        },
        windowElements: { self.elements[$0] ?? [] },
        makeWindow: { AXWindow(element: $0, application: $1, id: self.windowIds[$0] ?? 0) },
        focusedWindow: { self.systemFocusedWindow },
        focusedWindowOf: { app in
            self.focusedElements[app.processIdentifier].map {
                AXWindow(element: $0, application: app, id: self.windowIds[$0] ?? 0)
            }
        },
        isAlive: { !self.deadElements.contains($0) },
        screenIsLocked: { self.screenIsLocked }
    )

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
        watched[pid]?.filter { $0.notification == kAXWindowCreatedNotification }.count ?? 0
    }

    func notifications(pid: pid_t) -> [String] {
        watched[pid]?.map(\.notification) ?? []
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
