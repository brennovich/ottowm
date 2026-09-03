import AppKit
import ApplicationServices
import CoreGraphics

/// The applications watched, by pid. The registry is the one type of the AX stack that several
/// threads reach: a scan runs one thread per application (`RunningApplicationsObserver.scan`),
/// and each thread registers and looks up its own `Application` here, so the dictionary is
/// locked. `Application` has no lock and needs none: no two threads ever hold the same one,
/// because the scan blocks the main thread until every thread has returned, and every other
/// path into the stack, the AX notifications, the retries, the sweep and the focused-window
/// attach from `WindowSystem`, runs on the main thread.
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
        let windows = listedWindows(application.running).compactMap { window -> AXWindow? in
            guard case let .attached(attached) = application.attach(window) else { return nil }
            return attached
        }

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

        return application.attach(window).window
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    deinit {
        all.forEach { $0.invalidate() }
    }
}
