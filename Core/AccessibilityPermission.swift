import AppKit
import ApplicationServices

/// AccessibilityPermission probes what is a requirement for OttoWM, watching
/// for the AX permissions status of the process and offering controls to aid the
/// user to conced the trust to OttoWM.
struct AccessibilityPermission {
    enum Outcome {
        case granted
        case relaunching
        case quit
    }

    static let settingsCooldownSeconds: TimeInterval = 3

    var isTrusted: () -> Bool = { AXIsProcessTrusted() }
    var ask: (AccessibilityAlert.Request) -> AccessibilityAlert.Response = AccessibilityAlert.ask
    var openSettings: () -> Void = {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!,
            configuration: configuration,
            completionHandler: nil
        )
    }
    var wait: (TimeInterval) -> Void = { seconds in
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { RunLoop.current.run(mode: .default, before: deadline) }
    }
    var observeTrustChanges: (@escaping () -> Void) -> Void = { changed in
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { _ in DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: changed) }
    }
    let relaunch: () -> Void

    func request() -> Outcome {
        if isTrusted() { return .granted }
        Log.app.notice("accessibility permission missing")

        var relaunching = false
        observeTrustChanges {
            guard !relaunching, self.isTrusted() else { return }
            relaunching = true
            Log.app.notice("accessibility permission granted, relaunching")
            self.relaunch()
        }

        if ask(.openSettings) == .quit { return relaunching ? .relaunching : .quit }
        openSettings()
        wait(Self.settingsCooldownSeconds)
        if ask(.restart) == .quit { return relaunching ? .relaunching : .quit }

        relaunching = true
        relaunch()

        return .relaunching
    }

    func startWatchingTrust(lost: @escaping () -> Void, regained: @escaping () -> Void) {
        var trusted = true
        observeTrustChanges {
            guard trusted else {
                guard self.isTrusted() else { return }
                trusted = true
                Log.app.notice("accessibility permission restored, taking the event tap back")
                regained()
                return
            }

            guard !self.isTrusted() else { return }
            trusted = false
            Log.app.error("accessibility permission revoked, releasing the event tap")
            lost()
        }
    }
}
