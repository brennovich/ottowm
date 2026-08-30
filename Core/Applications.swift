import AppKit
import ApplicationServices
import CoreGraphics

final class Applications {
    struct AddedResult {
        let subscription: Subscription.Outcome
        let windows: [AXWindow]
        let focused: AXWindow?
    }

    private var applications: [pid_t: Application] = [:]
    private let lock = NSLock()

    private let focusedWindow: (NSRunningApplication) -> AXWindow?
    private let listedWindows: (NSRunningApplication) -> [AXWindow]

    init(
        focusedWindow: @escaping (NSRunningApplication) -> AXWindow? = AXWindow.focused(of:),
        listedWindows: @escaping (NSRunningApplication) -> [AXWindow] = AXWindow.all(of:)
    ) {
        self.focusedWindow = focusedWindow
        self.listedWindows = listedWindows
    }

    var all: [Application] { locked { Array(applications.values) } }

    func add(_ application: Application) -> AddedResult {
        locked { applications[application.pid] = application }

        let subscription = application.subscribe()
        guard subscription == .active else {
            return AddedResult(subscription: subscription, windows: [], focused: nil)
        }

        let focused = attachFocusedWindow(of: application)
        let windows = listedWindows(application.running).compactMap { application.attach($0) }

        return AddedResult(subscription: subscription, windows: windows, focused: focused)
    }

    func find(by pid: pid_t) -> Application? {
        locked { applications[pid] }
    }

    func remove(by pid: pid_t) {
        locked { applications.removeValue(forKey: pid) }?.invalidate()
    }

    func findWindow(by id: CGWindowID) -> AXWindow? {
        all.lazy.compactMap { $0.findWindow(by: id) }.first
    }

    private func attachFocusedWindow(of application: Application) -> AXWindow? {
        guard application.running.isActive, let window = focusedWindow(application.running)
        else { return nil }

        application.attach(window)
        return window
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    deinit {
        applications.values.forEach { $0.invalidate() }
    }
}
