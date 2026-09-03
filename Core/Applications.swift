import AppKit
import CoreGraphics

/// The applications watched, by pid. The registry is the one type of the AX stack that several
/// threads reach: a scan runs one thread per application (`RunningApplicationsObserver.scan`),
/// and each thread registers and looks up its own `Application` here, so the dictionary is
/// locked. `Application` has no lock and needs none: no two threads ever hold the same one,
/// because the scan blocks the main thread until every thread has returned, and every other
/// path into the stack, the AX notifications, the retries, the sweep and the focused-window
/// attach from `WindowSystem`, runs on the main thread.
final class Applications {
    private var applications: [pid_t: Application] = [:]
    private let lock = NSLock()

    var all: [Application] { locked { Array(applications.values) } }

    func add(_ application: Application) {
        locked { applications[application.pid] = application }
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

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    deinit {
        all.forEach { $0.invalidate() }
    }
}
