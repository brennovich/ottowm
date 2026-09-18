import AppKit
import CoreGraphics

/// The applications being watched, by pid. Thread safe because a scan runs one thread per
/// application (`RunningApplicationsObserver.scan`), and each thread registers and looks up
/// its own `Application`.
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
