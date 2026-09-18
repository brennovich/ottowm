import AppKit

/// The result of a scan. `focused` is kept out of `windows` so the caller can announce
/// it as a focus change.
struct ScanAttempt {
    let windows: [WindowSnapshot]
    let focused: WindowSnapshot?
    let subscription: Subscription.Outcome

    var all: [WindowSnapshot] { windows + (focused.map { [$0] } ?? []) }
}

/// The window events of the watched applications, and the scans that start, refresh and stop
/// watching one.
protocol WindowEvents: AnyObject {
    func startWatching(_ handler: @escaping (WindowEvent) -> Void)
    func start(_ app: NSRunningApplication) -> ScanAttempt?
    func stop(_ app: NSRunningApplication)
    func discover(_ app: NSRunningApplication) -> ScanAttempt?
    func inventory(_ app: NSRunningApplication) -> ScanAttempt?
    func sweepDeadWindows()
}
