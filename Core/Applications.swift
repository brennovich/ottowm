import AppKit
import CoreGraphics

/// The open and valid applications being managed, by pid. Thread safe registry that the AX stack
/// reaches several times: a scan runs one thread per application (`RunningApplicationsObserver.scan`),
/// and each thread registers and looks up its own `Application`.
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
