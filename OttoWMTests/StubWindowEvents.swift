import AppKit

/// Answers like `AXWindowEvents`: `start` returns nil for an application already watched or
/// one without a notification channel, `discover` and `inventory` return nil for an
/// application not watched, and `stop` forgets it.
final class StubWindowEvents: WindowEvents {
    enum Call: Equatable {
        case start(pid_t)
        case stop(pid_t)
        case discover(pid_t)
        case inventory(pid_t)
        case sweep
    }

    var scans: [pid_t: ScanAttempt] = [:]
    var failingNotificationPids: Set<pid_t> = []
    var onStart: (() -> Void)?

    // The start scan runs the applications on several threads at once, so what it
    // records is read and written from all of them.
    private let lock = NSLock()
    private var watched: Set<pid_t> = []
    private var recordedCalls: [Call] = []
    private var handlers: [(WindowEvent) -> Void] = []

    var calls: [Call] { locked { recordedCalls } }
    var startedPids: Set<pid_t> { Set(calls.compactMap { if case let .start(pid) = $0 { pid } else { nil } }) }

    func startWatching(_ handler: @escaping (WindowEvent) -> Void) {
        handlers.append(handler)
    }

    func start(_ app: NSRunningApplication) -> ScanAttempt? {
        let pid = app.processIdentifier
        onStart?()
        return locked {
            recordedCalls.append(.start(pid))
            guard !watched.contains(pid), !failingNotificationPids.contains(pid) else { return nil }
            watched.insert(pid)
            return scan(of: pid)
        }
    }

    func stop(_ app: NSRunningApplication) {
        locked {
            recordedCalls.append(.stop(app.processIdentifier))
            watched.remove(app.processIdentifier)
        }
    }

    func discover(_ app: NSRunningApplication) -> ScanAttempt? {
        locked {
            recordedCalls.append(.discover(app.processIdentifier))
            return watched.contains(app.processIdentifier) ? scan(of: app.processIdentifier) : nil
        }
    }

    func inventory(_ app: NSRunningApplication) -> ScanAttempt? {
        locked {
            recordedCalls.append(.inventory(app.processIdentifier))
            return watched.contains(app.processIdentifier) ? scan(of: app.processIdentifier) : nil
        }
    }

    func sweepDeadWindows() {
        locked { recordedCalls.append(.sweep) }
    }

    func report(_ event: WindowEvent) {
        for handler in handlers { handler(event) }
    }

    private func scan(of pid: pid_t) -> ScanAttempt {
        scans[pid] ?? ScanAttempt(windows: [], focused: nil, subscription: .active)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

extension ScanAttempt {
    static func active(_ windowIds: [CGWindowID], focused: CGWindowID? = nil) -> ScanAttempt {
        ScanAttempt(windows: windowIds.map { makeSnapshot($0) }, focused: focused.map { makeSnapshot($0) }, subscription: .active)
    }

    static let unreachable = ScanAttempt(windows: [], focused: nil, subscription: .unreachable)
    static let unsupported = ScanAttempt(windows: [], focused: nil, subscription: .unsupported)
}
