import AppKit

private let lockScreenBundleId = "com.apple.loginwindow"

// WebKit runs one of these XPC services per tab, per network session and per GPU
// context, so a browser accounts for dozens of them. None owns a window and none
// replies to the Accessibility API: every subscription attempt costs a full messaging
// timeout, and the retries spend it again until the grace period runs out. Universal
// Control behaves the same: it runs with or without a second device and owns no window.
private let silentBundleIds: Set<String> = [
    "com.apple.WebKit.WebContent",
    "com.apple.WebKit.Networking",
    "com.apple.WebKit.GPU",
    "com.apple.universalcontrol",
]

struct ApplicationFilter {
    private let ownPid: pid_t

    init(ownPid: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.ownPid = ownPid
    }

    func includes(_ app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        guard app.activationPolicy != .prohibited else {
            Log.observer.debug("skipping pid=\(pid) app=\(app.localizedName ?? ""): activation policy is prohibited")
            return false
        }
        guard pid != ownPid else { return false }
        guard let bundleId = app.bundleIdentifier else { return true }
        guard bundleId != lockScreenBundleId else {
            Log.observer.debug("skipping pid=\(pid) app=\(app.localizedName ?? ""): lock screen")
            return false
        }
        guard !silentBundleIds.contains(bundleId) else {
            Log.observer.debug("skipping pid=\(pid) app=\(app.localizedName ?? ""): replies to no accessibility call")
            return false
        }

        return true
    }
}
