import AppKit
import ApplicationServices

struct AccessibilityPermission {
    enum Request {
        case openSettings
        case restart
    }

    enum Response {
        case confirm
        case quit
    }

    enum Outcome {
        case granted
        case relaunching
        case quit
    }

    let isTrusted: () -> Bool
    let ask: (Request) -> Response
    let openSettings: () -> Void
    let watchForChange: (@escaping () -> Void) -> Void
    let relaunch: () -> Void

    func inquire() -> Outcome {
        if isTrusted() { return .granted }
        Log.app.notice("accessibility permission missing")

        var relaunching = false
        watchForChange {
            guard !relaunching, self.isTrusted() else { return }
            relaunching = true
            Log.app.notice("accessibility permission granted, relaunching")
            self.relaunch()
        }

        // A grant landing while an alert is up starts the relaunch behind it, and the
        // answer the user gives afterwards cannot cancel it.
        if ask(.openSettings) == .quit { return relaunching ? .relaunching : .quit }
        openSettings()
        if ask(.restart) == .quit { return relaunching ? .relaunching : .quit }

        relaunching = true
        relaunch()

        return .relaunching
    }

    func watchTrust(lost: @escaping () -> Void, regained: @escaping () -> Void) {
        var trusted = true
        watchForChange {
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

extension AccessibilityPermission {
    static func system() -> AccessibilityPermission {
        AccessibilityPermission(
            isTrusted: { AXIsProcessTrusted() },
            ask: { alertResponse(to: $0) },
            openSettings: {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!,
                    configuration: configuration,
                    completionHandler: nil
                )
            },
            watchForChange: { changed in
                DistributedNotificationCenter.default().addObserver(
                    forName: Notification.Name("com.apple.accessibility.api"),
                    object: nil,
                    queue: .main
                ) { _ in DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: changed) }
            },
            relaunch: {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(
                    at: Bundle.main.bundleURL, configuration: configuration
                ) { _, _ in exit(EXIT_SUCCESS) }
            }
        )
    }
}

private func alertResponse(to request: AccessibilityPermission.Request) -> AccessibilityPermission.Response {
    NSApp.setActivationPolicy(.regular)

    let alert = NSAlert()
    alert.alertStyle = .warning

    switch request {
    case .openSettings:
        alert.messageText = "OttoWM needs Accessibility permission"
        alert.informativeText = "Without it OttoWM cannot see or move a single window. Add OttoWM under Privacy & Security → Accessibility."
        alert.addButton(withTitle: "Open System Settings")
    case .restart:
        alert.messageText = "Grant access"
        alert.informativeText = "OttoWM restarts on its own once the permission is granted. Use this if it does not."
        alert.addButton(withTitle: "Restart OttoWM")
    }

    alert.addButton(withTitle: "Quit")
    alert.layout()

    // Ensute the alert is visible even if the app is not in the foreground or in full screen.
    alert.window.level = .floating
    alert.window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

    if request == .openSettings {
        NSApp.activate(ignoringOtherApps: true)
    }

    return alert.runModal() == .alertFirstButtonReturn ? .confirm : .quit
}
